# Linux NAS template / NAS 模板

Use a Linux amd64/arm64 NAS with Docker Compose v2. This builds locally; it does
not depend on a Home Tunnel client image being published. Keep the NAS firmware
and container runtime supported by their vendor.

1. Download the matching **7.0.0 Linux** archive and `SHA256SUMS.txt` from the client
   Release. Verify its hash (and the Sigstore checksum bundle), then extract it.
2. Copy this directory outside your checkout. Rename the extracted archive's
   top-level directory to `package` beside this Dockerfile. Do not mix Agent/CLI
   binaries from different packages: the CLI checks its Agent's hash.
3. Create the persistent directory: `mkdir -p data && sudo chown 10001:10001 data && chmod 700 data`.
4. Run `docker compose build`. In Web or Android create a ten-minute enrollment
   code. Enroll once using stdin so the code does not enter shell history:

   ```sh
   read -r -s -p 'Enrollment code: ' HT_CODE; printf '\n'
   printf '%s' "$HT_CODE" | docker compose run --rm -T client enroll \
     --state /data/state.json --server https://console.your-domain.net \
     --device-name home-nas --enrollment-code-file -
   unset HT_CODE
   docker compose up -d
   docker compose exec client status --state /data/state.json
   ```

Synology DSM: copy the directory into a restricted shared folder, use Container
Manager **Project** to import `compose.yaml`, and perform enrollment from SSH.
QNAP: import as a Compose application in Container Station; use its SSH terminal
for the one-time enrollment. Unraid: use Compose Manager or Docker CLI in a
restricted appdata directory. This is a Compose template, not a native SPK/QPKG
package or a Community Applications listing. Models without Compose v2 or amd64/
arm64 need a separate supported home host.

The host network lets the client reach `127.0.0.1` services on the NAS. For a
service in another container use its published host port. Do not enable privileged
mode or mount the Docker socket. Protect `data`: Linux headless storage uses file
permissions (0600), not an encrypted OS keychain. Only expose an application's
intended service port; keep NAS administration interfaces private.

升级：下载并验证整套新包，替换 `package`，重新 build 后 `up -d`；保留 `data`。
应用场景见主仓库 `docs/SCENARIOS.md`；服务端向导和预检见服务端 `docs/NAS.md`。
