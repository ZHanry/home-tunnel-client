# HOMEDESK: 只读预检，Compose config 不启动服务，不安装 CA 或改变网络配置。
from __future__ import annotations
import argparse
import json
import os
import re
import subprocess
from environment import ROOT, SERVICES, capture, check_materials, compose_command, docker_command, run_scope

DEFAULT_FIXTURES = {'http': 18090, 'https': 18454, 'tcp': 18091, 'udp': 18092}


def expected_ports(fixtures: dict) -> tuple[set, set]:
    return ({18443, 17000, fixtures['http'], fixtures['https'], fixtures['tcp'], *range(11000, 11010)},
            {fixtures['udp'], *range(11000, 11010)})


def validate_compose(value: dict, project: str, fixtures: dict | None = None) -> None:
    lock = json.loads((ROOT / 'lock.json').read_text(encoding='utf-8'))
    services = value.get('services', {})
    tcp, udp = expected_ports(fixtures or DEFAULT_FIXTURES)
    if value.get('name') != project or set(services) != SERVICES:
        raise ValueError('Compose 项目范围或服务清单发生变化')
    for name, service in services.items():
        expected = lock['images']['control-center' if name == 'fixture-backend' else name]
        if service.get('image') != expected or service.get('labels', {}).get('io.homedesk.acceptance.scope') != project:
            raise ValueError('Compose 镜像或验收标签不匹配')
        if service.get('network_mode') == 'host' or service.get('privileged'):
            raise ValueError('测试服务不得使用主机网络或特权模式')
        for port in service.get('ports', []):
            allowed = udp if port.get('protocol') == 'udp' else tcp
            numbers = str(port.get('published', '')).split('-')
            if not numbers or any(not number.isdigit() or int(number) not in allowed for number in numbers):
                raise ValueError('测试端口不在准备范围内')
            if port.get('host_ip') != '127.0.0.1':
                raise ValueError('默认准备包只能绑定回环地址')
    for kind in ['networks', 'volumes']:
        for name, resource in value.get(kind, {}).items():
            if resource.get('external') or resource.get('name') != f'{project}_{name}':
                raise ValueError('测试资源不得复用外部或非项目命名资源')
            if resource.get('labels', {}).get('io.homedesk.acceptance.scope') != project:
                raise ValueError('测试资源缺少范围标签')


def listener_ports(command: list[str], fixtures: dict) -> dict:
    if command[0] != 'wsl.exe' and os.name == 'nt':
        return {'checked': False, 'reason': '需要核对 Docker 实际宿主机端口'}
    prefix = ['wsl.exe', '--'] if command[0] == 'wsl.exe' else []
    occupied = {}
    tcp, udp = expected_ports(fixtures)
    for protocol, args, expected in [('tcp', ['ss', '-H', '-ltn'], tcp),
                                      ('udp', ['ss', '-H', '-lun'], udp)]:
        result = capture(prefix + args)
        if result.returncode != 0:
            return {'checked': False, 'reason': '无法只读取得宿主机监听端口'}
        ports = set()
        for line in result.stdout.splitlines():
            fields = line.split()
            if len(fields) >= 4:
                match = re.search(r':(\d+)$', fields[3])
                if match:
                    ports.add(int(match.group(1)))
        occupied[protocol] = sorted(ports & expected)
    return {'checked': True, 'occupied': occupied,
            'note': '这是CLI所在宿主机观察，不代替公网或跨VM连通性验证'}


def inspect(runtime: str) -> dict:
    path, data = run_scope(runtime)
    missing = check_materials(path, data, require_assets=False)
    private = path / 'secrets'
    if os.name != 'nt' and private.stat().st_mode & 0o077:
        raise ValueError('测试秘密父目录权限过宽')
    if os.name == 'nt':
        result = capture(['powershell.exe', '-NoProfile', '-NonInteractive', '-File',
            str(ROOT / 'permissions.ps1'), '-AcceptanceDirectory', str(path), '-Mode', 'Check'])
        if result.returncode != 0 or not json.loads(result.stdout).get('safe'):
            raise ValueError('测试目录的本机ACL未通过只读检查')
    result = {'scope': 'LOCAL_BACKEND_ONLY', 'project': data['project'],
              'official_assets_verified': not missing, 'missing_official_assets': missing,
              'runtime_launch_ready': False, 'private_directory_checked': True,
              'blocked_by': (["missing_official_assets"] if missing else []) +
                  ['isolated_windows_identity_not_confirmed', 'designated_tencent_instance_not_confirmed'],
              'started_by_this_tool': False, 'ops_business_cases_executed': 0,
              'isolated_windows_identity': 'not_confirmed'}
    command = docker_command()
    if command is None:
        return result | {'compose_config_checked': False, 'docker_available': False}
    version = capture(command + ['compose', 'version', '--short'])
    if version.returncode != 0 or not re.match(r'^v?2\.', version.stdout.strip()):
        raise ValueError('需要可用的 Docker Compose v2')
    result['compose_version'] = version.stdout.strip()
    config = capture(compose_command(path, command) + ['--profile', 'fixtures', 'config', '--format', 'json'])
    if config.returncode != 0:
        raise ValueError('Compose 静态配置检查失败')
    validate_compose(json.loads(config.stdout), data['project'], data['fixture_ports'])
    quiet = capture(compose_command(path, command) + ['--profile', 'fixtures', 'config', '--quiet'])
    if quiet.returncode != 0:
        raise ValueError('Compose config --quiet 未通过')
    result['compose_config_checked'] = True
    engine = capture(command + ['version', '--format', '{{.Server.Version}}'])
    result['docker_engine_query_ok'] = engine.returncode == 0
    if engine.returncode == 0:
        result['docker_engine_version'] = engine.stdout.strip()
        query = capture(command + ['ps', '-a', '--filter', f'label=com.docker.compose.project={path.name}', '--format', '{{.ID}}'])
        result['existing_project_containers'] = len(query.stdout.split()) if query.returncode == 0 else None
    result['ports'] = listener_ports(command, data['fixture_ports'])
    result['fixture_ports'] = data['fixture_ports']
    if not result['ports'].get('checked'):
        result['blocked_by'].append('docker_host_ports_not_confirmed')
    elif any(result['ports']['occupied'].values()):
        result['blocked_by'].append('test_ports_in_use')
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description='只读检查独立验收材料和 Docker 配置')
    parser.add_argument('--runtime', required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(inspect(args.runtime), ensure_ascii=False))
        return 0
    except Exception:
        print('预检未通过；没有启动服务、修改防火墙或输出秘密材料。')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
