"""Compile the small integration layer before compiling the complete engine."""
import re
import subprocess


def integration_objects(build):
    targets = set()
    for path in (build / "obj/home_tunnel_remote").rglob("*.ninja"):
        for line in path.read_text(encoding="utf-8").replace("$\n", "").splitlines():
            if not line.startswith("build ") or ": " not in line:
                continue
            outputs, _ = line[6:].split(": ", 1)
            for output in outputs.split():
                if re.fullmatch(r"obj/home_tunnel_remote/[A-Za-z0-9_./-]+\.(?:o|obj)", output) and ".." not in output.split("/"):
                    targets.add(output)
    return sorted(targets)


def build_logged(command, targets, build, cwd, env, log):
    first_party = integration_objects(build)
    stages = [(["-k", "0", *first_party], "integration objects")] if first_party else []
    stages.append((targets, "complete engine and integration"))
    with log.open("w", encoding="utf-8") as stream:
        for selected, label in stages:
            print(f"Compiling {label}; diagnostics: {log}", flush=True)
            stream.write(f"Build stage: {label}\n"); stream.flush()
            result = subprocess.run([*command, *selected], cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT)
            if result.returncode:
                return result.returncode
    return 0
