"""Execute Unix installer failures in a temporary, non-root filesystem fixture.

Only installation destinations and the root/platform preflight are rebased. The
production backup, mutation, rollback and signal handlers execute unchanged.
System service/account commands are mocked; no host installation is touched.
"""
from pathlib import Path
import hashlib
import os
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get("HT_TEST_BASH") or shutil.which("bash")


def shell_path(path):
    value = str(path).replace("\\", "/")
    if len(value) > 2 and value[1] == ":":
        return "/" + value[0].lower() + value[2:]
    return value


class InstallerUpgrade(unittest.TestCase):
    def run_fixture(self, platform, failure="", *, active_gui=False, restore_failure=False, native=True, corrupt_native=False):
        with tempfile.TemporaryDirectory(prefix="ht-installer-test-") as temp:
            work = Path(temp)
            package, filesystem, mocks = work / "package", work / "fs", work / "mocks"
            for directory in (package, filesystem, mocks, filesystem / "var/tmp"):
                directory.mkdir(parents=True, exist_ok=True)
            production = ROOT / ("packaging/install.sh" if platform == "linux" else "packaging/macos/install.sh")
            source = production.read_text(encoding="utf-8")
            root_check = 'if [[ ${EUID:-$(id -u)} -ne 0 ]]; then'
            self.assertEqual(source.count(root_check), 1, "installer preflight changed; review fixture isolation")
            source = source.replace(root_check, "if false; then")
            prefixes = ("/usr/local", "/etc/systemd", "/var/lib/home-tunnel", "/var/tmp", "/Library/LaunchDaemons")
            absolute = re.compile(r"(?<![}\w])(?:" + "|".join(re.escape(prefix) for prefix in prefixes) + ")")
            source = absolute.sub(lambda match: shell_path(filesystem) + match[0], source)
            entry = package / "install.sh"
            entry.write_text(source, encoding="utf-8", newline="\n")
            package_names = ["bin/home-tunnel-client", "bin/home-tunnel-gui", "lib/home-tunnel-agent", "libexec/home-tunnel-enroll"]
            targets = ["usr/local/bin/home-tunnel-client", "usr/local/bin/home-tunnel-gui", "usr/local/lib/home-tunnel/home-tunnel-agent", "usr/local/sbin/home-tunnel-enroll"]
            if platform == "linux":
                package_names += ["lib/systemd/system/home-tunnel-client.service", "lib/home-tunnel.desktop"]
                targets += ["etc/systemd/system/home-tunnel-client.service", "usr/local/share/applications/home-tunnel.desktop"]
                if native:
                    package_names += ["bin/home_tunnel_remote_host"]
                targets += ["usr/local/bin/home_tunnel_remote_host"]
                state = filesystem / "var/lib/home-tunnel/state.json"
            else:
                package_names += ["Library/LaunchDaemons/com.hometunnel.client.plist"]
                targets += ["Library/LaunchDaemons/com.hometunnel.client.plist"]
                state = filesystem / "usr/local/var/lib/home-tunnel/state.json"
            originals = {}
            for name in package_names:
                path = package / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("new version: " + name)
            if platform == "linux" and native:
                checksum = package / "native-remote/worker.sha256"
                checksum.parent.mkdir()
                digest = hashlib.sha256((package / "bin/home_tunnel_remote_host").read_bytes()).hexdigest()
                checksum.write_text(("0" * 64 if corrupt_native else digest) + "  bin/home_tunnel_remote_host\n", newline="\n")
            for name in targets:
                path = filesystem / name
                path.parent.mkdir(parents=True, exist_ok=True)
                originals[path] = ("old version: " + name).encode()
                path.write_bytes(originals[path])
            state.parent.mkdir(parents=True, exist_ok=True)
            state.write_bytes(b"unchanged device credentials")
            running = work / "service-running"
            running.touch()
            real = subprocess.run([BASH, "-c", "command -v cp; command -v install"], check=True, encoding="utf-8", capture_output=True, timeout=10).stdout.splitlines()
            self.assertEqual(len(real), 2)
            commands = {
                "uname": "printf 'Darwin\\n'\n",
                "id": "exit 0\n",
                "useradd": "exit 0\n",
                "dscl": "exit 0\n",
                "dseditgroup": "exit 0\n",
                "pgrep": 'exit "$HT_TEST_GUI_RESULT"\n',
                "systemctl": '''printf '%s\\n' "$*" >> "$HT_TEST_TRACE"
case "$1" in
 is-active) [[ -f "$HT_TEST_RUNNING" ]] ;;
 stop) rm -f -- "$HT_TEST_RUNNING" ;;
 start) touch "$HT_TEST_RUNNING" ;;
 daemon-reload) : ;;
 *) exit 90 ;;
esac
''',
                "launchctl": '''printf '%s\\n' "$*" >> "$HT_TEST_TRACE"
case "$1" in
 print) [[ -f "$HT_TEST_RUNNING" ]] ;;
 bootout) rm -f -- "$HT_TEST_RUNNING" ;;
 bootstrap) touch "$HT_TEST_RUNNING" ;;
 *) exit 90 ;;
esac
''',
                "cp": '''destination="${@: -1}"
source="${@: -2:1}"
if [[ "$destination" == */home-tunnel-install.*/* ]]; then
 count=0; if [[ -f "$HT_TEST_COUNT.backup" ]]; then count=$(<"$HT_TEST_COUNT.backup"); fi
 count=$((count+1)); printf '%s' "$count" > "$HT_TEST_COUNT.backup"
 if [[ "$HT_TEST_FAILURE" == backup && $count -eq 2 ]]; then exit 28; fi
elif [[ "$source" == */home-tunnel-install.*/* && "$HT_TEST_RESTORE_FAILURE" == 1 ]]; then
 exit 29
fi
"$HT_TEST_REAL_CP" "$@"
''',
                "install": '''args=(); directory=false
while [[ $# -gt 0 ]]; do
 case "$1" in
  -o|-g|-m) shift 2 ;;
  -d) directory=true; shift ;;
  *) args+=("$1"); shift ;;
 esac
done
if ! $directory; then
 count=0; if [[ -f "$HT_TEST_COUNT.install" ]]; then count=$(<"$HT_TEST_COUNT.install"); fi
 count=$((count+1)); printf '%s' "$count" > "$HT_TEST_COUNT.install"
 if [[ "$HT_TEST_FAILURE" == native-next && $count -eq 4 ]]; then exit 28; fi
 if [[ $count -eq 2 ]]; then
  if [[ "$HT_TEST_FAILURE" == install ]]; then exit 28; fi
  if [[ "$HT_TEST_FAILURE" == signal ]]; then kill -TERM "$PPID"; exit 143; fi
 fi
fi
if $directory; then
 mkdir -p -- "${args[@]}"
else
 "$HT_TEST_REAL_CP" -- "${args[@]}"
fi
''',
            }
            for name, body in commands.items():
                path = mocks / name
                path.write_text("#!/usr/bin/env bash\nset -Eeuo pipefail\n" + body, encoding="utf-8", newline="\n")
                path.chmod(0o755)
            env = dict(os.environ)
            env.update(HT_TEST_FAILURE=failure, HT_TEST_GUI_RESULT="0" if active_gui else "1",
                       HT_TEST_RESTORE_FAILURE="1" if restore_failure else "0", HT_TEST_REAL_CP=real[0],
                       HT_TEST_REAL_INSTALL=real[1], HT_TEST_RUNNING=shell_path(running),
                       HT_TEST_TRACE=shell_path(work / "trace"), HT_TEST_COUNT=shell_path(work / "count"),
                       HT_TEST_MOCKS=shell_path(mocks), HT_TEST_ENTRY=shell_path(entry))
            result = subprocess.run([BASH, "-c", 'export PATH="$HT_TEST_MOCKS:$PATH"; exec bash "$HT_TEST_ENTRY" --upgrade'],
                                    env=env, capture_output=True, encoding="utf-8", timeout=20)
            if not failure and not active_gui and not corrupt_native:
                self.assertEqual(result.returncode, 0, result.stderr)
                for path, old in originals.items():
                    if platform == "linux" and not native and path.name == "home_tunnel_remote_host":
                        self.assertFalse(path.exists(), "tunnel-only upgrade retained an older native worker")
                    else:
                        self.assertNotEqual(path.read_bytes(), old)
            else:
                self.assertNotEqual(result.returncode, 0, "failure did not stop installer")
                if failure and not restore_failure:
                    self.assertEqual(result.returncode, 143 if failure == "signal" else 28, result.stderr)
                    counter = "backup" if failure == "backup" else "install"
                    self.assertEqual((work / ("count." + counter)).read_text(), "4" if failure == "native-next" else "2")
                if not restore_failure:
                    for path, expected in originals.items():
                        self.assertTrue(path.is_file(), f"original was deleted: {path}; {result.stderr}")
                        self.assertEqual(path.read_bytes(), expected, f"original was changed: {path}")
            self.assertEqual(state.read_bytes(), b"unchanged device credentials")
            backups = list((filesystem / "var/tmp").glob("home-tunnel-install.*"))
            if restore_failure:
                self.assertEqual(len(backups), 1, result.stderr)
                self.assertEqual(len(list(backups[0].iterdir())), len(originals))
                self.assertIn("retained", result.stderr)
                self.assertFalse(running.exists(), "partially restored service was restarted")
            else:
                self.assertFalse(backups, "temporary backup was retained after complete recovery")
                self.assertTrue(running.exists(), "prior service state was not restored")
            if active_gui:
                self.assertIn("Choose Quit", result.stderr)
                self.assertFalse((work / "trace").exists(), "service was changed before GUI quit")
            if corrupt_native:
                self.assertIn("Native worker package verification failed", result.stderr)
                self.assertFalse((work / "trace").exists(), "corrupt native package changed the service")
            if failure == "backup":
                trace = (work / "trace").read_text()
                self.assertNotIn("stop", trace)
                self.assertNotIn("bootout", trace)

    def test_failure_recovery(self):
        for platform in ("linux", "macos"):
            for failure in ("backup", "install", "signal"):
                with self.subTest(platform=platform, failure=failure):
                    self.run_fixture(platform, failure)

    def test_failed_restore_preserves_backup_and_stopped_service(self):
        for platform in ("linux", "macos"):
            with self.subTest(platform=platform):
                self.run_fixture(platform, "install", restore_failure=True)

    def test_active_gui_prevents_upgrade(self):
        for platform in ("linux", "macos"):
            with self.subTest(platform=platform):
                self.run_fixture(platform, active_gui=True)

    def test_success_replaces_full_package_and_preserves_credentials(self):
        for platform in ("linux", "macos"):
            with self.subTest(platform=platform):
                self.run_fixture(platform)

    def test_linux_native_worker_is_restored_after_later_install_failure(self):
        self.run_fixture("linux", "native-next")

    def test_linux_corrupt_native_worker_is_rejected_before_mutation(self):
        self.run_fixture("linux", corrupt_native=True)

    def test_linux_tunnel_only_package_remains_independent(self):
        self.run_fixture("linux", native=False)


if __name__ == "__main__":
    if not BASH:
        raise SystemExit("Bash is required for installer failure-injection tests")
    unittest.main()
