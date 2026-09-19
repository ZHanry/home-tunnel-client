#!/usr/bin/env bash
# Sourced by build-release.sh. Secrets are provided by the release environment.
signing_directory=""
signing_mode="unsigned-no-certificate-configured"
init_signing() {
  if [[ -z "${MACOS_DEVELOPER_ID_P12_BASE64:-}" ]]; then
    [[ "${REQUIRE_PLATFORM_SIGNING:-false}" != true && -z "${MACOS_DEVELOPER_ID_PASSWORD:-}${MACOS_SIGNING_IDENTITY:-}${APPLE_NOTARY_KEY_P8_BASE64:-}${APPLE_NOTARY_KEY_ID:-}${APPLE_NOTARY_ISSUER_ID:-}" ]] || { echo "macOS publishing identity is incomplete or required" >&2; return 1; }
    echo "No Developer ID configured; macOS artifacts are explicitly unsigned."
    return
  fi
  for name in MACOS_DEVELOPER_ID_PASSWORD MACOS_SIGNING_IDENTITY APPLE_NOTARY_KEY_P8_BASE64 APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID; do
    [[ -n "${!name:-}" ]] || { echo "Missing signing/notarization setting: $name" >&2; return 1; }
  done
  signing_directory=$(mktemp -d "${TMPDIR:-/tmp}/home-tunnel-signing.XXXXXX")
  signing_keychain="$signing_directory/release.keychain-db"
  local keychain_password
  keychain_password=$(openssl rand -hex 32)
  printf '%s' "$MACOS_DEVELOPER_ID_P12_BASE64" | base64 -D > "$signing_directory/identity.p12"
  printf '%s' "$APPLE_NOTARY_KEY_P8_BASE64" | base64 -D > "$signing_directory/notary.p8"
  chmod 600 "$signing_directory/identity.p12" "$signing_directory/notary.p8"
  security create-keychain -p "$keychain_password" "$signing_keychain"
  security set-keychain-settings -lut 21600 "$signing_keychain"
  security unlock-keychain -p "$keychain_password" "$signing_keychain"
  security import "$signing_directory/identity.p12" -k "$signing_keychain" -P "$MACOS_DEVELOPER_ID_PASSWORD" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$signing_keychain" >/dev/null
  signing_mode="developer-id-notarized"
}
sign_macos_binary() {
  [[ -n "$signing_directory" ]] || return 0
  codesign --force --options runtime --timestamp --keychain "$signing_keychain" --sign "$MACOS_SIGNING_IDENTITY" "$1"
  codesign --verify --strict --verbose=2 "$1"
}
notarize_macos_package() {
  local package="$1"
  if [[ -n "$signing_directory" ]]; then
    ditto -c -k --keepParent "$package" "$signing_directory/notarize.zip"
    xcrun notarytool submit "$signing_directory/notarize.zip" --key "$signing_directory/notary.p8" \
      --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID" --wait --timeout 30m --output-format json > "$signing_directory/notary.json"
    python3 - "$signing_directory/notary.json" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
if result.get('status')!='Accepted':raise SystemExit('Apple notarization was not accepted')
PY
    cp "$signing_directory/notary.json" "$package/notarization.json"
  fi
  printf '{"platform":"macos","mode":"%s","offline_stapling":false}\n' "$signing_mode" > "$package/platform-signing.json"
}
cleanup_signing() {
  if [[ -n "$signing_directory" ]]; then
    security delete-keychain "$signing_keychain" || true
    rm -f -- "$signing_directory/identity.p12" "$signing_directory/notary.p8" "$signing_directory/notarize.zip" "$signing_directory/notary.json"
    rmdir "$signing_directory" || true
  fi
}
