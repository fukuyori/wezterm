# Windows Release build and installer

Run these commands in PowerShell from the repository root. The scripts require
Windows and PowerShell 5.1 or later. They do not install dependencies or initialize
Git submodules automatically.

## Release build

Requirements: Rust's `x86_64-pc-windows-msvc` toolchain, Visual Studio's
**Desktop development with C++** workload (including the Windows SDK and CMake),
and native Windows Strawberry Perl.

```powershell
git submodule update --init --recursive
.\scripts\build-release.ps1
```

The script builds `wezterm.exe`, `wezterm-gui.exe`, `wezterm-mux-server.exe` and
`strip-ansi-escapes.exe` in `target\release` with `--release --locked`. Cargo may
download missing dependencies. It enters the Visual Studio x64 developer
environment if `cl.exe` is not already on PATH. Run with the x64 MSVC Rust
toolchain and without a Cargo `build.target` override or `CARGO_BUILD_TARGET`.

Perl is located in `C:\Strawberry`, the local
`target\build-tools\strawberry-perl` directory, or PATH. To select another copy:

```powershell
.\scripts\build-release.ps1 -PerlPath C:\Tools\Strawberry\perl\bin\perl.exe
```

## Installer

Install Inno Setup 6. Package the existing Release build separately:

```powershell
.\scripts\build-installer.ps1 -Sign
```

`-Sign` requires Windows SDK `signtool.exe` and `CODESIGN_CERT` containing the
**subject name** of a valid code-signing certificate with a private key in
`Cert:\CurrentUser\My`. This follows the subject selection used by `signtool /n`;
it is not a PFX filename or password. Hardware-token certificates may prompt for
their PIN through the certificate provider. The scripts do not store PINs or
passwords.

The script copies the payload into a unique work directory and signs the four
WezTerm executables there. It retains Microsoft's signature on `OpenConsole.exe`.
Inno Setup calls `scripts\sign-windows.ps1` for both Setup and Uninstall, with
`SignedUninstaller=yes`. Each signing operation requires SHA-256, an RFC 3161
timestamp, and successful signature verification. A signing failure stops the
package; it does not fall back to an unsigned installer.

The default timestamp service is `http://timestamp.digicert.com`. Override it with
`-TimestampUrl`. Tools can be selected using `-IsccPath` and `-SignToolPath`.
`-BinaryDir` defaults to `target\release`; `-OutputDir` defaults to
`target\installer`. Relative paths are resolved from the repository root,
regardless of the working directory.

The version comes from the packaged `wezterm.exe --version`. Output files are:

- `target\installer\WezTerm-<version>-x64-setup.exe`
- `target\installer\WezTerm-<version>-x64-setup.exe.sha256`

Unique staging and compiler output directories remain under
`target\installer\work` for inspection. A completed run replaces the installer
with the same version in the output directory. The installer retains the upstream
AppId and installs to Program Files, so it updates an existing WezTerm installation
and requires administrator privileges when installed. Packaging itself does not
install or launch WezTerm.

For a local packaging test without signing:

```powershell
.\scripts\build-installer.ps1 -OutputDir target\installer-test
```

This produces an unsigned test installer. Use `-Sign` for distribution. An actual
install/uninstall test and a hardware-backed signing run are separate from an
unsigned packaging test.

The installer includes `LICENSE.md`, the `licenses` directory and the bundled font
license texts. See also [the version update checklist](version-update-checklist.md).

Signing references: [Inno Setup SignTool](https://jrsoftware.org/ishelp/topic_setup_signtool.htm),
[SignedUninstaller](https://jrsoftware.org/ishelp/topic_setup_signeduninstaller.htm),
and [Microsoft SignTool](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool).
