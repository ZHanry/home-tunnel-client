#!/usr/bin/env python3
"""在回环地址验证本地 Console 镜像和持久化；只使用临时测试数据。"""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
TOKEN = 'test-only-token-00000000000000000000'

def main():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    name = 'homedesk-console-test-' + uuid.uuid4().hex[:12]
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    def request(path, data=None):
        req = urllib.request.Request(f'http://127.0.0.1:{port}{path}', data=None if data is None else json.dumps(data).encode(), headers={'Authorization': 'Bearer '+TOKEN, 'Content-Type': 'application/json'})
        with opener.open(req, timeout=3) as response:
            return json.load(response)
    def ready():
        for _ in range(50):
            try:
                return request('/api/v1/devices')
            except (OSError, urllib.error.URLError):
                time.sleep(.1)
        raise RuntimeError('测试容器未就绪')
    with tempfile.TemporaryDirectory(prefix='container-test-', dir=ROOT/'target') as storage:
        subprocess.run(['docker','run','--detach','--rm','--name',name,'--network','host','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges:true','--user',f'{os.getuid()}:{os.getgid()}','--mount',f'type=bind,src={storage},dst=/data','-e','BIND_IP=127.0.0.1','-e',f'PORT={port}','-e',f'TOKEN={TOKEN}','-e','NET_CIDR=192.168.50.0/24','-e','DB_PATH=/data/test.sqlite3','homedesk/console:0.1.0'],check=True,stdout=subprocess.DEVNULL)
        try:
            assert ready() == []
            assert request('/api/v1/heartbeat',{'id':'container-test','hostname':'容器测试','platform':'Linux','arch':'x86_64','version':'test','ip':'192.168.50.2','mac':''})['ok']
            subprocess.run(['docker','restart',name],check=True,stdout=subprocess.DEVNULL)
            devices=ready()
            assert len(devices)==1 and devices[0]['id']=='container-test'
            print('通过：静态镜像启动、非 root/只读容器、API 鉴权与心跳、容器重启数据持久化。')
        finally:
            subprocess.run(['docker','stop',name],check=True,stdout=subprocess.DEVNULL)

if __name__=='__main__':main()
