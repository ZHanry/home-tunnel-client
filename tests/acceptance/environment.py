# HOMEDESK: 验收准备工具共用的范围检查；不读取现用配置或修改运行服务。
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / '.runtime'
SERVICES = {'control-center', 'traffic-gateway', 'frps', 'caddy', 'fixture-backend'}
PROJECT = re.compile(r'^hd-portal-acceptance-[a-z0-9][a-z0-9_-]{0,48}$')
SCOPE_LABEL = 'io.homedesk.acceptance.scope'


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def run_scope(value: str | Path, *, require_manifest: bool = True) -> tuple[Path, dict]:
    raw = Path(value).absolute()
    if RUNTIME.is_symlink() or raw.is_symlink():
        raise ValueError('拒绝符号链接形式的验收目录')
    path = raw.resolve()
    if path.parent != RUNTIME.resolve() or not PROJECT.fullmatch(path.name):
        raise ValueError('验收目录必须位于本准备包的 .runtime 下并使用专用项目名')
    if not require_manifest:
        return path, {}
    data = json.loads((path / 'prepared.json').read_text(encoding='utf-8'))
    if data.get('schema_version') != 1 or data.get('project') != path.name or data.get('scope') != 'LOCAL_BACKEND_ONLY':
        raise ValueError('验收范围记录无效')
    if data.get('lock_sha256') != digest(ROOT / 'lock.json'):
        raise ValueError('准备材料与当前发行锁文件不一致')
    return path, data


def capture(command: list[str], *, timeout: int = 30) -> subprocess.CompletedProcess:
    # 调用方只发布固定状态；不转发工具可能包含路径或凭据的完整错误输出。
    return subprocess.run(command, capture_output=True, text=True, encoding='utf-8',
                          errors='replace', timeout=timeout, check=False)


def docker_command() -> list[str] | None:
    if shutil.which('docker'):
        return ['docker']
    if shutil.which('wsl.exe'):
        try:
            result = capture(['wsl.exe', '--', 'docker', 'compose', 'version', '--short'])
            if result.returncode == 0:
                return ['wsl.exe', '--', 'docker']
        except (OSError, subprocess.TimeoutExpired):
            pass
    return None


def docker_path(path: Path, command: list[str]) -> str:
    if command[0] != 'wsl.exe':
        return str(path)
    result = capture(['wsl.exe', '--', 'wslpath', '-a', path.as_posix()])
    if result.returncode != 0:
        raise ValueError('无法为 WSL 转换验收路径')
    return result.stdout.strip()


def compose_command(path: Path, command: list[str]) -> list[str]:
    return command + ['compose', '-p', path.name, '--project-directory', docker_path(path, command),
                      '--env-file', docker_path(path / '.env', command),
                      '-f', docker_path(path / 'compose.yaml', command)]


def check_materials(path: Path, data: dict, *, require_assets: bool = True) -> list[str]:
    lock = json.loads((ROOT / 'lock.json').read_text(encoding='utf-8'))
    missing = []
    for asset in lock['assets']:
        file = path / 'artifacts' / asset['name']
        if not file.exists():
            missing.append(asset['name'])
            continue
        if file.is_symlink() or digest(file) != asset['sha256']:
            raise ValueError('官方发行物未通过摘要检查')
    if require_assets and missing:
        raise ValueError('官方发行物未齐全，不能运行后端探针')
    for name, expected in data['template_sha256'].items():
        file = path / name
        if file.is_symlink() or digest(file) != expected:
            raise ValueError('验收配置已变化，必须重新审阅并准备')
    for name in data['private_files']:
        file = path / name
        if file.is_symlink() or not file.is_file() or not 24 <= file.stat().st_size <= 65536:
            raise ValueError('测试秘密材料缺失或范围无效')
    return missing
