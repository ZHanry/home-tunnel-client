# HOMEDESK: 默认只列清理计划；--execute 仍须全部资源通过名称及双标签检查。
from __future__ import annotations
import argparse
import json
import re
from environment import SERVICES, SCOPE_LABEL, capture, check_materials, compose_command, docker_command, run_scope
from preflight import validate_compose


def validate_resource(kind: str, value: dict, project: str) -> None:
    labels = value.get('Config', {}).get('Labels', {}) if kind == 'container' else value.get('Labels', {})
    if labels.get('com.docker.compose.project') != project or labels.get(SCOPE_LABEL) != project:
        raise ValueError('资源不是本验收项目拥有，拒绝清理')
    name = value.get('Name', '').lstrip('/')
    if kind == 'container':
        if labels.get('com.docker.compose.service') not in SERVICES or not name.startswith((project + '-', project + '_')):
            raise ValueError('容器不在验收服务范围')
    elif kind == 'volume':
        if name != project + '_sqlite-data':
            raise ValueError('拒绝清理非验收数据卷')
    elif name not in [project + '_control', project + '_edge']:
        raise ValueError('拒绝清理非验收网络')


def cleanup(runtime: str, execute: bool) -> dict:
    path, data = run_scope(runtime)
    check_materials(path, data, require_assets=False)
    command = docker_command()
    if command is None:
        raise ValueError('Docker 不可用，未执行清理')
    config = capture(compose_command(path, command) + ['--profile', 'fixtures', 'config', '--format', 'json'])
    if config.returncode != 0:
        raise ValueError('Compose 配置检查失败')
    validate_compose(json.loads(config.stdout), path.name, data['fixture_ports'])
    counts = {}
    for kind, listing in [('container', ['ps', '-a', '--format', '{{.ID}}']),
                          ('volume', ['volume', 'ls', '-q']), ('network', ['network', 'ls', '-q'])]:
        query = capture(command + listing + ['--filter', f'label=com.docker.compose.project={path.name}'])
        if query.returncode != 0:
            raise ValueError('无法核验全部项目资源，拒绝清理')
        identifiers = query.stdout.split()
        for identifier in identifiers:
            if not re.fullmatch(r'[a-zA-Z0-9_.-]+', identifier):
                raise ValueError('资源标识无效')
            inspected = capture(command + [kind, 'inspect', identifier])
            if inspected.returncode != 0:
                raise ValueError('资源检查失败，拒绝清理')
            values = json.loads(inspected.stdout)
            if len(values) != 1:
                raise ValueError('资源范围不唯一')
            validate_resource(kind, values[0], path.name)
        counts[kind] = len(identifiers)
    if execute and any(counts.values()):
        # 只操作已审阅的这份 Compose，不枚举路径后交给另一种 shell 删除。
        completed = capture(compose_command(path, command) + ['--profile', 'fixtures', 'down', '--volumes'], timeout=60)
        if completed.returncode != 0:
            raise ValueError('清理未完成，保留材料供人工检查')
    return {'project': path.name, 'scope': 'LOCAL_BACKEND_ONLY', 'verified_resources': counts,
            'executed': execute and any(counts.values()), 'runtime_files_deleted': False}


def main() -> int:
    parser = argparse.ArgumentParser(description='仅清理该独立验收项目拥有的 Docker 资源')
    parser.add_argument('--runtime', required=True)
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args()
    try:
        print(json.dumps(cleanup(args.runtime, args.execute), ensure_ascii=False))
        return 0
    except Exception:
        print('未完成清理；范围核验失败或 Docker 不可用，未输出资源详情或秘密。')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
