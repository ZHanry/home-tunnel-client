"""Build the native Linux Xorg candidate and run isolated Xvfb evidence.

The production worker is packaged separately from the test-only worker. Xvfb
results never establish acceptance on a physical Xorg desktop or on Wayland.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import select
import shutil
import struct
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "native/remote"


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def source_identity():
    """Bind the copied overlay and build recipes, including development edits."""
    paths = list(NATIVE.rglob("*")) + [ROOT / "scripts" / name for name in (
        "build-native-linux.py", "build-remote-webrtc.py", "generate-remote-notices.py")]
    paths.append(ROOT / "internal/model/model.go")
    entries = {path.relative_to(ROOT).as_posix(): sha(path) for path in paths if path.is_file()}
    return hashlib.sha256(json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def recipe():
    value = json.loads((NATIVE / "linux/linux-build.lock.json").read_text())
    if (value["schema_version"] != 1 or value["target_os"] != "linux" or
            value["target_cpu"] != "x64" or
            value["upstream_lock_sha256"] != sha(NATIVE / "remote-deps.lock.json") or
            value["gn_args"] != {"rtc_use_x11": True, "rtc_use_pipewire": False, "use_sysroot": False}):
        raise SystemExit("Linux Xorg recipe differs from the reviewed source lock")
    return value


def run(command, **kwargs):
    return subprocess.run([str(item) for item in command], check=True, **kwargs)


def host_ipc(executable, expected_available):
    process = subprocess.Popen([str(executable), "--host-inherited-pipe"],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, bufsize=0)
    events = []
    sequence = 0

    def exact(count, deadline):
        value = b""
        while len(value) < count:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([process.stdout], [], [], remaining)[0]:
                raise RuntimeError("Native host IPC timed out")
            part = os.read(process.stdout.fileno(), count - len(value))
            if not part:
                raise RuntimeError("Native host IPC ended unexpectedly")
            value += part
        return value

    def request(operation, payload):
        nonlocal sequence
        sequence += 1
        body = json.dumps({"abi": 1, "id": sequence, "operation": operation,
                           "payload": payload}, separators=(",", ":")).encode()
        process.stdin.write(struct.pack(">I", len(body)) + body)
        deadline = time.monotonic() + 10
        while True:
            count, = struct.unpack(">I", exact(4, deadline))
            if not 0 < count <= 262144:
                raise RuntimeError("Unbounded native host response")
            response = json.loads(exact(count, deadline))
            if response.get("abi") != 1:
                raise RuntimeError("Native host ABI mismatch")
            if response.get("id") == sequence:
                return response
            if "event" not in response or len(events) >= 16:
                raise RuntimeError("Unexpected native host event")
            events.append(response)

    try:
        hello = request("hello", {})
        if not hello.get("ok") or hello["result"].get("abi") != 1:
            raise RuntimeError("Native hello failed")
        response = request("capabilities", {})
        caps = response.get("result", {})
        if not response.get("ok") or caps.get("available") is not expected_available:
            raise RuntimeError("Production/test desktop boundary failed")
        if expected_available:
            if (caps.get("status") != "ready" or not caps.get("displays") or
                    caps.get("permissions") != ["view", "input.keyboard", "input.pointer"] or
                    caps.get("codecs") != ["H264", "VP8"]):
                raise RuntimeError("Native Linux capabilities differ from the implemented surface")
            ref = {"session_id": "a0000000-0000-4000-8000-000000000001", "connection_epoch": 1}
            prepared = request("prepare", ref)
            if not prepared.get("ok"):
                raise RuntimeError("Native Linux preparation failed")
            if request("start", ref).get("ok"):
                raise RuntimeError("Unsigned native session was accepted")
        elif caps.get("permissions") or caps.get("displays"):
            raise RuntimeError("Unavailable production worker exposed a desktop capability")
        process.stdin.close()
        if process.wait(timeout=10) != 0:
            raise RuntimeError("Native worker did not shut down cleanly")
        return {"hello": "passed", "capability_boundary": "passed",
                "unsigned_authorization": "rejected" if expected_available else "not_started"}
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
        process.stdout.close()
        if not process.stdin.closed:
            process.stdin.close()


def isolated_tests(build, output):
    if os.environ.get("HT_RD_XVFB_ISOLATED_TEST") != "1" or not os.environ.get("DISPLAY", "").startswith(":"):
        raise SystemExit("Isolated tests require the explicit separate Xvfb environment")
    evidence = {"schema_version": 1, "status": "failed", "scope": "isolated-xvfb",
                "physical_xorg_acceptance": False, "wayland_acceptance": False,
                "production_worker_sha256": sha(build / "home_tunnel_remote_host"),
                "test_worker_sha256": sha(build / "home_tunnel_remote_host_xvfb"),
                "input_test_sha256": sha(build / "home_tunnel_x11_input_tests"),
                "recipe_sha256": sha(NATIVE / "linux/linux-build.lock.json")}
    try:
        result = run([build / "home_tunnel_x11_input_tests"], capture_output=True, text=True, timeout=20)
        evidence["input"] = json.loads(result.stdout)
        evidence["production_ipc"] = host_ipc(build / "home_tunnel_remote_host", False)
        evidence["test_ipc"] = host_ipc(build / "home_tunnel_remote_host_xvfb", True)
        for codec in ("H264", "VP8"):
            result = subprocess.run([str(build / "home_tunnel_webrtc_probe"), "--local-desktop-loopback", "--codec=" + codec],
                                    capture_output=True, text=True, timeout=90)
            probe = json.loads(result.stdout) if result.stdout.strip() else {"status": "failed"}
            probe.update({"exit_code": result.returncode, "probe_sha256": sha(build / "home_tunnel_webrtc_probe"),
                          "scope": "isolated-xvfb-local-udp-loopback", "physical_xorg_acceptance": False})
            evidence[codec] = probe
            if result.returncode:
                # The isolated probe disables WebRTC debug logging and never
                # saves frames. Retain bounded fatal-stage diagnostics in CI.
                print(result.stderr[-4096:], file=sys.stderr)
                raise RuntimeError("Isolated " + codec + " capture/encode/decode failed")
        evidence["status"] = "passed"
    finally:
        (output / "linux-xvfb-evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print("Linux isolated Xvfb capture/codecs/IPC/input passed; physical Xorg remains unaccepted")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--build", action="store_true")
    mode.add_argument("--build-existing", action="store_true")
    parser.add_argument("--cache", type=Path, default=ROOT / ".downloads/remote-webrtc-linux")
    parser.add_argument("--output", type=Path, default=ROOT / "outputs/native-linux-build")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--isolated-tests", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    recipe()
    if not 1 <= args.jobs <= 64:
        parser.error("Use 1..64 build jobs")
    if not args.build and not args.build_existing and not args.isolated_tests:
        print("Linux Xorg recipe matches the immutable upstream lock")
        return
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "AMD64"):
        raise SystemExit("Linux native builds require a Linux x64 host")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if args.isolated_tests:
        isolated_tests(args.isolated_tests.resolve(), output)
        return
    cache = args.cache.resolve()
    cache.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(cache).free < 24 * 1024 ** 3:
        raise SystemExit("The pinned native build requires 24 GiB free space")
    mode = "--build" if args.build else "--build-existing"
    before = source_identity()
    run([sys.executable, ROOT / "scripts/build-remote-webrtc.py", mode, "--target-os", "linux",
         "--target-cpu", "x64", "--cache", cache, "--jobs", args.jobs, "--media-probe"], cwd=ROOT)
    build = cache / "checkout/src/out/home_tunnel"
    env = dict(os.environ, HT_RD_XVFB_ISOLATED_TEST="1", XDG_SESSION_TYPE="x11")
    for name in ("WAYLAND_DISPLAY", "XDG_SESSION_ID", "DBUS_SYSTEM_BUS_ADDRESS"):
        env.pop(name, None)
    run(["xvfb-run", "-a", "-s", "-screen 0 800x600x24 -nolisten tcp", sys.executable,
         Path(__file__).resolve(), "--isolated-tests", build, "--output", output], env=env, cwd=ROOT)
    # The test worker and its bypass are intentionally excluded from candidate
    # distribution. Evidence binds its hash separately from the real worker.
    for name in ("home_tunnel_remote_host", "remote-host-build.json", "remote-source-manifest.json",
                 "remote-webrtc-build.json", "LICENSE.md"):
        shutil.copy2(build / name, output / name)
    record_path = output / "remote-host-build.json"
    record = json.loads(record_path.read_text())
    if source_identity() != before:
        raise SystemExit("Native source changed during the build; rebuild the candidate from a fixed checkout")
    record["executable"] = str(output / "home_tunnel_remote_host")
    record["linux_source_tree_sha256"] = before
    record["isolated_xvfb_evidence_sha256"] = sha(output / "linux-xvfb-evidence.json")
    record["physical_xorg_acceptance"] = False
    record_path.write_text(json.dumps(record, indent=2) + "\n")
    libraries = run(["ldd", output / "home_tunnel_remote_host"], capture_output=True, text=True).stdout
    if "not found" in libraries:
        raise SystemExit("Native worker has unresolved runtime libraries")
    (output / "runtime-libraries.txt").write_text(libraries)
    print("Linux native candidate built with isolated evidence; physical desktop acceptance is still required")


if __name__ == "__main__":
    main()
