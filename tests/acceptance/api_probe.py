# HOMEDESK: 运行后只探测真实测试 API；不创建业务资源、不落盘或输出登录令牌。
from __future__ import annotations
import argparse
import getpass
import json
import ssl
import urllib.error
import urllib.request
from environment import check_materials, run_scope


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, url):
        raise ValueError('不允许API重定向')


def probe(runtime: str, username: str | None) -> dict:
    path, data = run_scope(runtime)
    check_materials(path, data)
    # 仅该探针进程加载新生成 CA，不安装系统 CA、不关闭主机名或证书校验。
    context = ssl.create_default_context(cafile=str(path / 'secrets/ca.crt'))
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect(),
                                         urllib.request.HTTPSHandler(context=context))
    origin = 'https://127.0.0.1:18443'
    if data['origin'] != origin:
        raise ValueError('只允许准备包的固定测试origin')

    def request(route: str, body: dict | None = None, token: str | None = None):
        headers = {'Accept': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        encoded = None if body is None else json.dumps(body).encode('utf-8')
        if encoded is not None:
            headers['Content-Type'] = 'application/json'
        call = urllib.request.Request(origin + '/api/v1' + route, data=encoded, headers=headers)
        with opener.open(call, timeout=5) as response:
            raw = response.read(1024 * 1024 + 1)
            if len(raw) > 1024 * 1024:
                raise ValueError('响应超过探针限额')
            return None if not raw else json.loads(raw)

    capabilities = request('/public/capabilities')
    if capabilities.get('server_version') != '10.1.0' or capabilities.get('contract_version') != '1.5.0':
        raise ValueError('运行版本与锁定契约不符')
    report = {'scope': 'LOCAL_BACKEND_ONLY', 'server_version': '10.1.0', 'contract_version': '1.5.0',
              'tls_verified_with_process_test_ca': True, 'windows_exe_tested': False,
              'ops_business_cases_executed': 0}
    if username:
        password = getpass.getpass('专用测试账号密码（不回显）：')
        mfa = getpass.getpass('人工 MFA 验证码或恢复码，可留空（不回显）：')
        session = request('/auth/login', {'username': username, 'password': password,
            'client_type': 'linux', **({'mfa_code': mfa} if mfa else {})})
        token = session['access_token']
        try:
            identity = request('/auth/me', token=token)
            if identity.get('device_id') is not None or identity.get('native_remote'):
                raise ValueError('不是账号管理会话')
            report['account_identity_verified'] = True
            for resource in ['devices', 'connections']:
                first = request('/client/' + resource + '?page=1&page_size=100', token=token)
                count = len(first['items'])
                if first['total'] > 1000 or first['total_pages'] > 10:
                    raise ValueError('目录超过测试限额')
                for page in range(2, first['total_pages'] + 1):
                    value = request('/client/' + resource + f'?page={page}&page_size=100', token=token)
                    count += len(value['items'])
                if count != first['total']:
                    raise ValueError('目录在读取时变化')
                report[resource + '_count'] = count
        finally:
            request('/auth/session/close', {}, token=token)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description='后续人工启动后使用的本地真实API探针')
    parser.add_argument('--runtime', required=True)
    parser.add_argument('--username')
    args = parser.parse_args()
    try:
        print(json.dumps(probe(args.runtime, args.username), ensure_ascii=False))
        return 0
    except Exception:
        print('真实后端探针未通过；不显示服务端任意错误、密码、验证码或令牌，不自动重放登录。')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
