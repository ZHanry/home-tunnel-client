"""Use the pinned upstream license mapping for the exact native host GN target."""
import argparse
import importlib.util
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--gn", type=Path, required=True)
    args = parser.parse_args()
    source, build, gn = args.source.resolve(), args.build.resolve(), args.gn.resolve()
    script = source / "tools_webrtc/libs/generate_licenses.py"
    spec = importlib.util.spec_from_file_location("pinned_webrtc_licenses", script)
    upstream = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(upstream)
    # Our overlay is intentionally outside WebRTC's default //:default root.
    # Use the same explicit root as its build; do not alter upstream sources.
    def describe(directory, target):
        return subprocess.check_output([str(gn), "desc", "--root-target=//home_tunnel_remote/webrtc",
                                        "--all", "--format=json", directory, target], cwd=source, text=True)
    upstream.LicenseBuilder._run_gn = staticmethod(describe)
    licenses = dict(upstream.LIB_TO_LICENSES_DICT)
    # The pinned upstream's generator omits the optional proprietary-codec
    # dependencies. Use the License File values in their pinned README.chromium.
    licenses["ffmpeg"] = ["third_party/ffmpeg/CREDITS.chromium", "third_party/ffmpeg/COPYING.LGPLv2.1"]
    licenses["openh264"] = ["third_party/openh264/src/LICENSE"]
    upstream.LicenseBuilder([str(build)], ["//home_tunnel_remote/webrtc:home_tunnel_remote_host"], licenses).generate_license_text(str(build))


if __name__ == "__main__":
    main()
