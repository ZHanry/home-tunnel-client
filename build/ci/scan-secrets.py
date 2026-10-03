#!/usr/bin/env python3
"""仅扫描 Git 可提交文件，跳过被忽略的真实配置、数据卷及构建缓存；输出脱敏。"""
import argparse
import json
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gitleaks',default='gitleaks')
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[2]
    baseline_path=Path(__file__).with_name('gitleaks-baseline.json')
    baseline=json.loads(baseline_path.read_text(encoding='utf-8')) if baseline_path.is_file() else {}
    raw=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=root)
    with tempfile.TemporaryDirectory(prefix='homedesk-secret-scan-') as temp:
        for path in raw.decode('utf-8').split('\0'):
            if not path:continue
            source=root/path
            if source.is_file() and not source.is_symlink() and source.resolve().is_relative_to(root):
                destination=Path(temp)/path
                destination.parent.mkdir(parents=True,exist_ok=True)
                shutil.copyfile(source,destination)
        report=Path(temp)/'gitleaks-report.json'
        result=subprocess.run([args.gitleaks,'dir',temp,'--redact','--no-banner','--max-target-megabytes','1','--report-format','json','--report-path',str(report)],cwd=root)
        unexpected=0
        reviewed=0
        if result.returncode and report.is_file():
            # Gitleaks JSON 固定为 UTF-8；Windows 默认代码页会破坏中文路径，导致基线匹配失败。
            for finding in json.loads(report.read_text(encoding='utf-8')):
                path=Path(finding['File'])
                try:path=path.relative_to(temp)
                except ValueError:pass
                saved=baseline.get(path.as_posix(),{})
                source=root/path
                checksum=hashlib.sha256(source.read_bytes().replace(b'\r\n',b'\n')).hexdigest() if source.is_file() else ''
                if finding['RuleID']=='generic-api-key' and checksum==saved.get('sha256') and finding['StartLine'] in saved.get('lines',[]):
                    reviewed+=1
                    continue
                unexpected+=1
                print(f"{path}:{finding['StartLine']} [{finding['RuleID']}]",flush=True)
            print(f'已核对上游公钥示例/测试夹具：{reviewed}；新增或变化的疑似密钥：{unexpected}',flush=True)
            if result.returncode==1:return 1 if unexpected else 0
        return result.returncode

if __name__=='__main__':raise SystemExit(main())
