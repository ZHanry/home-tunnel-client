# Contributing

The shared Windows/macOS/Linux GUI, CLI and managed FRP Agent.

This repository owns its code, tests and component releases. The project overview,
downloads and cross-component roadmap live at https://github.com/ZHanry/home-tunnel.

## Local checks

```sh
go test ./...
go vet ./...
go build ./cmd/home-tunnel-client
pnpm install --frozen-lockfile
pnpm exec playwright install chromium
pnpm run lint && pnpm run test:browser
```

Go 1.26.6 is pinned. Native Linux GUI builds need GTK 3 and WebKitGTK 4.1;
macOS uses WebKit and Windows uses WebView2. The headless CLI builds without CGO.

Keep changes focused, update the relevant tests and documentation, and explain
changes to authentication, leases, Agent validation, signing or update trust.
Generated binaries, credentials and local configuration must remain untracked.
Pull requests never receive release signing secrets.

## Versions and compatibility

Only this component's version is changed for a component release. API v1 is the
initial compatibility boundary; see `compatibility.json` and `docs/RELEASING.md`.
The original project history remains available under the upstream `v5.0.0` tag.
