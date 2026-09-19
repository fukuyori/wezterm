#requires -Version 5.1
<#
.SYNOPSIS
Builds the Windows x64 Release executables in target\release.
.EXAMPLE
.\scripts\build-release.ps1
.EXAMPLE
.\scripts\build-release.ps1 -PerlPath C:\Strawberry\perl\bin\perl.exe
#>
[CmdletBinding()]
param([string]$PerlPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if ($env:OS -ne 'Windows_NT') { throw 'Run this script on Windows.' }
$rustInfo = & rustc -vV
if ($LASTEXITCODE -ne 0 -or $rustInfo -notcontains 'host: x86_64-pc-windows-msvc') {
    throw 'Select the x86_64-pc-windows-msvc Rust toolchain before building.'
}
if ($env:CARGO_BUILD_TARGET) {
    throw 'Unset CARGO_BUILD_TARGET; this script builds the native x64 host into target\release.'
}
foreach ($submoduleFile in @('deps\freetype\freetype2\include\ft2build.h',
    'deps\freetype\libpng\png.h', 'deps\freetype\zlib\zlib.h', 'deps\harfbuzz\harfbuzz\src\hb.h')) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $submoduleFile))) {
        throw 'Missing submodules. Run: git submodule update --init --recursive'
    }
}
if (-not $PerlPath) {
    $candidates = @('C:\Strawberry\perl\bin\perl.exe',
        (Join-Path $repoRoot 'target\build-tools\strawberry-perl\perl\bin\perl.exe'))
    $onPath = Get-Command perl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($onPath) { $candidates += $onPath.Source }
    $PerlPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if (-not $PerlPath -or -not (Test-Path -LiteralPath $PerlPath -PathType Leaf)) {
    throw 'Install Strawberry Perl or pass -PerlPath with the full path to its perl.exe.'
}
$PerlPath = (Resolve-Path -LiteralPath $PerlPath).Path
$oldPath = $env:Path
$oldLcAll = $env:LC_ALL
$oldLcCtype = $env:LC_CTYPE
Push-Location $repoRoot
try {
    if (-not (Get-Command cl.exe -CommandType Application -ErrorAction SilentlyContinue)) {
        $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Install Visual Studio with Desktop development with C++.' }
        $vsDirectory = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($LASTEXITCODE -ne 0 -or -not $vsDirectory) { throw 'The Visual Studio C++ toolchain was not found.' }
        & (Join-Path $vsDirectory 'Common7\Tools\Launch-VsDevShell.ps1') -Arch amd64 -HostArch amd64 -SkipAutomaticLocation
    }
    $env:Path = (Split-Path -Parent $PerlPath) + ';' + $env:Path
    $env:LC_ALL = 'C'
    $env:LC_CTYPE = 'C'
    $perlPlatform = & $PerlPath -e 'print $^O'
    if ($LASTEXITCODE -ne 0 -or $perlPlatform -ne 'MSWin32') { throw 'A native Windows Perl is required (not MSYS/Cygwin Perl).' }
    & cargo build --release --locked --target-dir (Join-Path $repoRoot 'target') `
        -p wezterm -p wezterm-gui -p wezterm-mux-server -p strip-ansi-escapes
    if ($LASTEXITCODE -ne 0) { throw "Release build failed (exit $LASTEXITCODE)." }
    foreach ($file in @('wezterm.exe', 'wezterm-gui.exe', 'wezterm-mux-server.exe', 'strip-ansi-escapes.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "target\release\$file"))) {
            throw "Missing target\release\$file. Check Cargo's build.target configuration."
        }
    }
    & .\target\release\wezterm.exe --version
    if ($LASTEXITCODE -ne 0) { throw 'The built wezterm.exe did not start successfully.' }
} finally {
    Pop-Location
    $env:Path = $oldPath
    $env:LC_ALL = $oldLcAll
    $env:LC_CTYPE = $oldLcCtype
}
