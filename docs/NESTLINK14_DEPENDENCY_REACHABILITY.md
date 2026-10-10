# Native Rust dependency review for 14.0.0

The Linux GUI is part of this release. The historical Windows/Android scope in
`HOMEDESK_DEPENDENCIES.md` does not describe the 14.0.0 Linux packages.
`build/ci/build-client.py` enables `flutter,hwcodec,unix-file-copy-paste` for both
Linux architectures. The pinned build toolchain is Rust 1.96.0. Cargo builds and
the dependency trees use the workspace `client/Cargo.lock` with `--locked`.

| Package | Linux selection and review | Release action |
| --- | --- | --- |
| `fuser` | The Linux file clipboard compiles `clipboard::platform::unix::fuse` and calls `spawn_mount2`. The 0.15.1 package was selected by the actual release features. RUSTSEC-2021-0154 / GHSA-cvmj-47v9-35m9 concerns the libfuse session constructor; this project disables the `libfuse` feature. | Upgrade to fixed 0.16.0, retaining file clipboard support and the existing read-only mount options. The implemented `Filesystem` methods and `spawn_mount2` retain compatible signatures. Its minimum Rust version is 1.85, covered by the pinned 1.96 toolchain. |
| `users` 0.11.0 | A direct Linux dependency of `hbb_common`; product code calls `get_current_uid`, `get_user_by_uid` and `get_user_by_name`, and reads user fields through `UserExt`. | The group-listing functions affected by RUSTSEC-2025-0040 / GHSA-m65q-v92h-cm7q are not called in product code. The group-member pointer traversal affected by RUSTSEC-2023-0059 / GHSA-jcr6-4frq-9gjj belongs to group lookup, also absent from these paths. This is a call-site review, not a patched-package claim. The package remains unmaintained. |
| `users` 0.10.0 | Selected by the pinned `pam` fork. Its `src/client.rs` calls `get_user_by_name` and reads `UserExt` fields when setting up a PAM session. | The fork does not call `get_user_groups`, `get_current_groups`, `get_group_by_name`, `get_group_by_gid`, or `User::groups`. The same group-specific advisory assessment applies; the package itself remains unchanged. |
| `glib` 0.18.5 | Linked through the GTK 3 ecosystem. Product `src/platform/gtk_sudo.rs` uses widgets, `clone!`, timers, propagation and control-flow types. | RUSTSEC-2024-0429 / GHSA-wrw7-89jp-8q8g affects `VariantStrIter` iteration, obtained through `Variant::array_iter_str`. No product or inspected GTK/GIO/libappindicator call sites use that iterator. The dependency remains affected by version. A direct 0.20 upgrade cannot replace GTK 3's 0.18 ecosystem without a wider migration or audited backport. |
| `git2` 0.16.1 / `libgit2-sys` 0.14.2+1.5.1 | Present in the Linux **build** graph: `keepawake` build script calls `shadow-rs::new`, whose default `git2` feature reads the local checkout's HEAD, commit, author and status. They are not normal runtime dependencies of the GUI. | The inspected generator does not call `Repository::revparse_single`, `Index::add`, `Remote::list`, `Blame::blame_buffer`, or create/dereference a new `Buf`; it performs no Git network operation. These package versions remain below some advisory fixes. This limits the reviewed release exposure to build inputs; it does not declare the packages fixed. |
| `rpassword` 2.1.0 | Selected solely by `quest` in `scrap`'s non-Android dev dependencies. `quest` is used by `libs/scrap/examples/record-screen.rs`. | Absent from the official GUI's `cargo tree -e normal,build` graph. The example and its password-reading helper are not compiled into the shipped GUI. |

The review inspected the selected package sources, the pinned `pam` and
`keepawake` Git revisions, and product call sites. `users` group lookups and
`glib` variant-string iteration must be reviewed again before new callers are
added. Reachability findings do not remove GitHub alerts or replace package
maintenance. The release materials contain vendored sources and platform
dependency trees so the findings can be checked against the built source.

Validation must include the Linux clipboard package with
`--features unix-file-copy-paste`, and the official native Linux builds with all
three release features. Runtime installation and media acceptance are separate
from this dependency review.
