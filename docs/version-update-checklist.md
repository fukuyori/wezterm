# Version update checklist

WezTerm's application release identifier is derived from `.tag`, when present,
or the Git commit timestamp and short hash. The workspace crates' Cargo package
versions are separate; do not replace all of them with an installer version.

| File | Role / action when changing version policy |
| --- | --- |
| `.tag` (optional, ignored by Git) | Overrides the application release identifier; update or remove deliberately before building. |
| `wezterm-version/build.rs` | Embeds the application identifier and Rust target. |
| `wezterm-gui/build.rs` | Embeds Windows executable version metadata. |
| `scripts/build-installer.ps1` | Reads the built CLI version and derives the installer filename and `MyAppVersion`. |
| `ci/windows-installer.iss` | Uses `MyAppVersion` for the installer; no duplicate release string is maintained here. |
| `ci/deploy.sh` | Upstream packaging path derives its version from Git/tag information. |
| Relevant crate `Cargo.toml` files and `Cargo.lock` | Update only when changing the corresponding Cargo package version/dependencies. |
| `docs/windows-build.md` and `docs/install/source.md` | Keep commands, paths, prerequisites and signing behavior synchronized. |

Before packaging, rebuild the application and check
`target\release\wezterm.exe --version` and the GUI executable's Windows file
properties. Package using `scripts\build-installer.ps1 -Sign`, check signature
verification succeeds, and verify the installer filename/version and SHA-256 file.
Retain the licenses. Validate installation and uninstallation separately before
distribution.

Creating a Git commit, tag, push or release requires an explicit request.
