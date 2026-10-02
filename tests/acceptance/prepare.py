# HOMEDESK: 只下载校验并生成独立材料；绝不启动 Docker、Agent 或交付 EXE。
from __future__ import annotations
import argparse
import csv
from datetime import datetime, timedelta, timezone
import io
import json
import os
from pathlib import Path, PurePosixPath
import secrets
import shutil
import stat
import subprocess
import tarfile
import urllib.request
from urllib.parse import urlsplit
from environment import ROOT, RUNTIME, PROJECT, capture, digest, run_scope


def secure_directory(path: Path) -> str:
    path.mkdir(mode=0o700, parents=True, exist_ok=False)
    if os.name != 'nt':
        path.chmod(0o700)
        return 'posix-0700'
    result = capture(['whoami', '/user', '/fo', 'csv', '/nh'])
    rows = list(csv.reader(io.StringIO(result.stdout)))
    if result.returncode != 0 or not rows or not rows[0][-1].startswith('S-1-'):
        raise ValueError('无法确定新建目录的本机访问主体')
    sid = rows[0][-1]
    result = capture(['icacls', str(path), '/inheritance:r', '/grant:r', f'*{sid}:(OI)(CI)F'])
    if result.returncode != 0:
        raise ValueError('无法限制新建验收目录的访问权限')
    return 'windows-current-sid-acl'


def fetch(asset: dict, destination: Path) -> None:
    url = urlsplit(asset['url'])
    if url.scheme != 'https' or url.netloc != 'github.com' or url.query or url.fragment or not url.path.startswith((
        '/ZHanry/home-tunnel-server/releases/download/v10.1.0/',
        '/ZHanry/home-tunnel-client/releases/download/v10.1.0/')):
        raise ValueError('只允许固定官方发行地址')
    own_run, _ = run_scope(destination.parent.parent, require_manifest=False)
    if not destination.resolve().is_relative_to(own_run):
        raise ValueError('下载目标不在专用项目目录')
    if destination.exists():
        if digest(destination) == asset['sha256']:
            return
        raise ValueError('既有发行文件摘要不匹配，拒绝覆盖')
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    request = urllib.request.Request(asset['url'], headers={'User-Agent': 'HomeDesk-Acceptance-Prepare/1'})
    partial = destination.with_suffix(destination.suffix + '.partial')
    total = 0
    try:
        with opener.open(request, timeout=15) as response, partial.open('xb') as handle:
            for chunk in iter(lambda: response.read(1024 * 1024), b''):
                total += len(chunk)
                if total > 128 * 1024 * 1024:
                    raise ValueError('发行文件超过准备包下载限额')
                handle.write(chunk)
    except Exception:
        if os.name != 'nt':
            raise
        # 仅删除本次创建的公开下载临时文件；验证绝对目标仍在专用项目目录。
        run_scope(destination.parent.parent, require_manifest=False)
        if partial.is_symlink():
            raise ValueError('拒绝符号链接下载临时文件')
        partial.unlink(missing_ok=True)
        result = capture(['powershell.exe', '-NoProfile', '-NonInteractive', '-File',
            str(ROOT / 'download.ps1'), '-Uri', asset['url'], '-Destination', str(partial)], timeout=75)
        if result.returncode != 0:
            partial.unlink(missing_ok=True)
            if not shutil.which('wsl.exe'):
                raise ValueError('官方发行物原生下载也未完成')
            converted = capture(['wsl.exe', '--', 'wslpath', '-a', partial.as_posix()])
            if converted.returncode != 0:
                raise ValueError('无法为原生下载转换专用目录')
            result = capture(['wsl.exe', '--', 'curl', '--fail', '--location', '--silent',
                '--show-error', '--max-time', '45', '--output', converted.stdout.strip(), asset['url']], timeout=60)
            if result.returncode != 0:
                raise ValueError('官方发行物所有标准TLS下载通道均未完成')
    if digest(partial) != asset['sha256']:
        raise ValueError('下载文件摘要不匹配，未准备成功')
    partial.replace(destination)


def extract_regular(archive: Path, destination: Path) -> list[str]:
    destination.mkdir(mode=0o700)
    skipped = []
    with tarfile.open(archive, 'r:gz') as bundle:
        members = bundle.getmembers()
        if len(members) > 10000 or sum(member.size for member in members) > 512 * 1024 * 1024:
            raise ValueError('发行包解压超过限额')
        for member in members:
            name = PurePosixPath(member.name)
            if name.is_absolute() or '..' in name.parts or '\\' in member.name or ':' in member.name:
                raise ValueError('发行包含有越界路径')
            target = destination.joinpath(*name.parts).resolve()
            if not target.is_relative_to(destination.resolve()):
                raise ValueError('发行包解压目录越界')
            if member.isdir():
                target.mkdir(mode=0o700, parents=True, exist_ok=True)
            elif member.isfile():
                target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                stream = bundle.extractfile(member)
                if stream is None:
                    raise ValueError('发行包普通文件无法读取')
                with target.open('xb') as handle:
                    shutil.copyfileobj(stream, handle)
                target.chmod(0o755 if member.mode & 0o111 else 0o644)
            else:
                # 不在 Windows 上创建需额外权限的链接；原始已验证 tar 仍完整保留。
                skipped.append(member.name)
    return skipped


def openssl_call(executable: str, args: list[str]) -> None:
    result = capture([executable] + args)
    if result.returncode != 0:
        raise ValueError('生成测试证书失败，未输出工具日志或私钥')


def certificates(path: Path, executable: str, project: str) -> None:
    secret = path / 'secrets'
    ca = secret / 'ca.crt'
    ca_key = secret / 'ca.key'
    openssl_call(executable, ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-days', '14',
        '-subj', '/CN=HomeDesk Acceptance Local CA', '-addext', 'basicConstraints=critical,CA:TRUE',
        '-keyout', str(ca_key), '-out', str(ca)])
    ext = secret / 'edge.ext'
    ext.write_text('basicConstraints=critical,CA:FALSE\nextendedKeyUsage=serverAuth\n'
        'subjectAltName=DNS:localhost,DNS:console.acceptance.test,DNS:*.services.acceptance.test,IP:127.0.0.1\n', encoding='ascii')
    openssl_call(executable, ['req', '-new', '-newkey', 'rsa:2048', '-nodes', '-sha256',
        '-subj', '/CN=localhost', '-keyout', str(secret / 'edge.key'), '-out', str(secret / 'edge.csr')])
    openssl_call(executable, ['x509', '-req', '-sha256', '-days', '14', '-in', str(secret / 'edge.csr'),
        '-CA', str(ca), '-CAkey', str(ca_key), '-CAcreateserial', '-extfile', str(ext), '-out', str(secret / 'edge.crt')])
    # 与官方 FRPS 信任材料形态一致，独立自签证书只用于该新测试栈。
    openssl_call(executable, ['req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256',
        '-nodes', '-sha256', '-days', '14', '-subj', '/CN=127.0.0.1',
        '-addext', 'subjectAltName=IP:127.0.0.1,DNS:frps', '-keyout', str(secret / 'frps_tls_key.pem'),
        '-out', str(secret / 'frps_tls_cert.pem')])
    openssl_call(executable, ['verify', '-CAfile', str(ca), str(secret / 'edge.crt')])
    # 主机上的私有父目录保护 0644 文件；单个文件挂载后 uid10001 才可读取。
    for file in secret.iterdir():
        file.chmod(0o600 if file.name == 'ca.key' else 0o644)
    secret.chmod(0o700)


def validate_metadata(path: Path, lock: dict) -> None:
    for component in ['server', 'client']:
        value = json.loads((path / 'artifacts' / f'{component}-release-manifest.json').read_text(encoding='utf-8'))
        if value.get('component') != component or value.get('version') != '10.1.0' or value.get('revision') != lock[f'{component}_revision']:
            raise ValueError('官方发行元数据的版本或源码来源不匹配')
    value = json.loads((path / 'artifacts/frps-dependency.json').read_text(encoding='utf-8'))
    if value.get('version') != '0.70.1' or lock['images']['frps'] != value.get('image', '') + '@' + value.get('digest', ''):
        raise ValueError('官方 FRPS 元数据不匹配')
    override = (path / 'artifacts/compose.release.yaml').read_text(encoding='utf-8')
    if not all(lock['images'][name] in override for name in ['control-center', 'traffic-gateway']):
        raise ValueError('官方发行镜像与准备包固定镜像不一致')


def prepare(project: str, *, openssl: str | None = None, config_only: bool = False,
            reuse_artifacts: str | None = None, fixture_ports: dict | None = None) -> dict:
    if not PROJECT.fullmatch(project):
        raise ValueError('项目名必须使用 hd-portal-acceptance- 安全前缀')
    executable = openssl or shutil.which('openssl')
    if not executable:
        raise ValueError('需要现有 OpenSSL；准备包不安装工具或改系统信任')
    fixture_ports = fixture_ports or {'http': 18090, 'https': 18454, 'tcp': 18091, 'udp': 18092}
    reserved = {17000, 18443, *range(11000, 11010)}
    if (set(fixture_ports) != {'http', 'https', 'tcp', 'udp'} or
        any(not isinstance(port, int) or not 1 <= port <= 65535 or port in reserved for port in fixture_ports.values()) or
        len({fixture_ports[name] for name in ['http', 'https', 'tcp']}) != 3):
        raise ValueError('临时后端端口无效或冲突')
    RUNTIME.mkdir(mode=0o700, exist_ok=True)
    path, _ = run_scope(RUNTIME / project, require_manifest=False)
    protection = secure_directory(path)
    for directory in ['artifacts', 'secrets', 'downloads']:
        (path / directory).mkdir(mode=0o700)
    lock = json.loads((ROOT / 'lock.json').read_text(encoding='utf-8'))
    skipped = {}
    if reuse_artifacts:
        source, _ = run_scope(reuse_artifacts, require_manifest=False)
        for asset in lock['assets']:
            file = source / 'artifacts' / asset['name']
            if file.is_file():
                if file.is_symlink() or not file.resolve().is_relative_to(source) or digest(file) != asset['sha256']:
                    raise ValueError('拒绝复用越界或未验证的发行文件')
                shutil.copyfile(file, path / 'artifacts' / asset['name'])
    if not config_only:
        for asset in lock['assets']:
            fetch(asset, path / 'artifacts' / asset['name'])
        validate_metadata(path, lock)
        for component, name in [('server', 'home-tunnel-server-10.1.0.tar.gz'),
                                ('client', 'home-tunnel-linux-10.1.0-amd64.tar.gz')]:
            skipped[component] = extract_regular(path / 'artifacts' / name, path / f'upstream-{component}')
    for name in ['internal_service_key', 'frps_plugin_key', 'lease_signing_key']:
        (path / 'secrets' / name).write_text(secrets.token_hex(32) + '\n', encoding='ascii')
    (path / 'secrets/bootstrap_admin_password').write_text('Ht-' + secrets.token_hex(18) + '-A7!\n', encoding='ascii')
    certificates(path, executable, project)
    if os.name == 'nt':
        protected = capture(['powershell.exe', '-NoProfile', '-NonInteractive', '-File',
            str(ROOT / 'permissions.ps1'), '-AcceptanceDirectory', str(path), '-Mode', 'Secure'])
        if protected.returncode != 0:
            raise ValueError('新测试秘密文件ACL限制失败')
        protection = 'windows-owner-system-administrators-acl'
    for name in ['compose.yaml', 'Caddyfile', 'backend.mjs']:
        shutil.copyfile(ROOT / name, path / name)
    environment = {'ACCEPTANCE_PROJECT': project, 'CONTROL_IMAGE': lock['images']['control-center'],
        'GATEWAY_IMAGE': lock['images']['traffic-gateway'], 'FRPS_IMAGE': lock['images']['frps'],
        'CADDY_IMAGE': lock['images']['caddy']}
    environment.update({f'FIXTURE_{name.upper()}_PORT': port for name, port in fixture_ports.items()})
    (path / '.env').write_text(''.join(f'{key}={value}\n' for key, value in environment.items()), encoding='utf-8')
    (path / '.env').chmod(0o600)
    data = {'schema_version': 1, 'project': project, 'scope': 'LOCAL_BACKEND_ONLY',
        'prepared': not config_only, 'config_prepared': True,
        'official_assets_complete': not config_only, 'started': False, 'ops_business_cases_executed': 0,
        'origin': 'https://127.0.0.1:18443', 'directory_protection': protection,
        'fixture_ports': fixture_ports,
        'lock_sha256': digest(ROOT / 'lock.json'),
        'template_sha256': {name: digest(path / name) for name in ['compose.yaml', 'Caddyfile', 'backend.mjs', '.env']},
        'private_files': ['secrets/internal_service_key', 'secrets/frps_plugin_key', 'secrets/lease_signing_key',
            'secrets/bootstrap_admin_password', 'secrets/ca.key', 'secrets/edge.key', 'secrets/frps_tls_key.pem'],
        'archive_links_not_created': skipped,
        'tls_trust': 'process_ca_only_not_installed', 'isolated_windows_identity': 'not_confirmed'}
    (path / 'prepared.json').write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return data


def main() -> int:
    parser = argparse.ArgumentParser(description='准备独立验收材料，不启动任何服务')
    parser.add_argument('--project')
    parser.add_argument('--openssl')
    parser.add_argument('--config-only', action='store_true', help='只准备本地配置并明确阻止发行物完成声明')
    parser.add_argument('--reuse-artifacts', help='只复用本包运行目录下已经通过锁文件摘要的公开发行物')
    parser.add_argument('--fixture-http-port', type=int, default=18090)
    parser.add_argument('--fixture-https-port', type=int, default=18454)
    parser.add_argument('--fixture-tcp-port', type=int, default=18091)
    parser.add_argument('--fixture-udp-port', type=int, default=18092)
    args = parser.parse_args()
    stamp = datetime.now(timezone(timedelta(hours=8))).strftime('%Y%m%d')
    project = args.project or f'hd-portal-acceptance-{stamp}-{secrets.token_hex(3)}'
    try:
        result = prepare(project, openssl=args.openssl, config_only=args.config_only,
                         reuse_artifacts=args.reuse_artifacts,
                         fixture_ports={'http': args.fixture_http_port, 'https': args.fixture_https_port,
                           'tcp': args.fixture_tcp_port, 'udp': args.fixture_udp_port})
        print(json.dumps({'project': result['project'], 'prepared': result['prepared'],
                          'config_prepared': True, 'official_assets_complete': result['official_assets_complete'], 'started': False,
                          'ops_business_cases_executed': 0}, ensure_ascii=False))
        return 0
    except Exception:
        # 不把 URL 查询串、路径、OpenSSL 输出或秘密材料带入聊天日志。
        print('准备未完成；现有文件保留，未启动任何服务。请检查下载、摘要及工具条件。')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
