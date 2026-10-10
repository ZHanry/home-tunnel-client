# Local desktop development workflow

The current work is NestLink 14.0.0 desktop development. Develop, test and install locally first. Do not push commits, upload build artifacts, create GitHub tags or publish releases until the user explicitly approves that upload.

Before **every local installation**, use `packaging/windows/install-local-clean.ps1`: back up the previous app/configuration outside the repository, stop its processes, uninstall it, remove its remaining installation/configuration and matching shortcuts, then install fresh and verify the build receipt. Do not perform an overlay install on this user's machine. A clean install requires a new sign-in; do not silently restore old credentials into it.

Keep the existing account and remote authorization checks when changing UI. `brand/icon.svg` is the shared desktop icon source. See `docs/DESKTOP_14_LOCAL.md` for the local scope and build/install workflow. The more specific `client/AGENTS.md` continues to apply to the Rust/Flutter client.
