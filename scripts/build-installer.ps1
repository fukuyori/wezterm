#requires -Version 5.1
<#
.SYNOPSIS
Packages an existing Windows x64 Release build with Inno Setup.
.DESCRIPTION
-Sign signs staged WezTerm executables, Setup and Uninstall using the
CurrentUser certificate store subject selected by CODESIGN_CERT. The original
build files are preserved. Relative paths are resolved from the repository root.
.EXAMPLE
.\scripts\build-installer.ps1 -Sign
.EXAMPLE
.\scripts\build-installer.ps1 -OutputDir target\installer-test
#>
[CmdletBinding()]
param(
    [switch]$Sign,
    [string]$BinaryDir = 'target\release',
    [string]$OutputDir = 'target\installer',
    [string]$IsccPath,
    [string]$SignToolPath,
    [ValidatePattern('^https?://[^\s"\r\n]+$')]
    [string]$TimestampUrl = 'http://timestamp.digicert.com'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath([string]$Path) {
    if (-not [IO.Path]::IsPathRooted($Path)) { $Path = Join-Path $repoRoot $Path }
    return [IO.Path]::GetFullPath($Path)
}

function Resolve-Tool([string]$ExplicitPath, [string]$Name, [string[]]$Candidates) {
    if ($ExplicitPath) {
        $resolved = Resolve-RepoPath $ExplicitPath
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            throw "Tool not found: $resolved"
        }
        return $resolved
    }
    $onPath = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($onPath) { return $onPath.Source }
    foreach ($candidate in $Candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw "$Name was not found. Install it or specify its path explicitly."
}

function Assert-X64Executable([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) { throw "Not a PE file: $Path" }
        $stream.Position = 0x3C
        $stream.Position = $reader.ReadUInt32()
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) {
            throw "Expected a Windows x64 binary: $Path"
        }
    } finally { $reader.Dispose() }
}

function Quote-InnoArgument([string]$Value) {
    if ($Value -match '["\r\n]') { throw 'Quotes and newlines are not supported in signing command paths.' }
    # Inno expands $q / $f / $p. Escape literal dollars before adding quotes.
    return '$q' + $Value.Replace('$', '$$') + '$q'
}

if ($env:OS -ne 'Windows_NT') { throw 'Run this script on Windows.' }
$binaryRoot = Resolve-RepoPath $BinaryDir
$outputRoot = Resolve-RepoPath $OutputDir
$ownExecutables = @('wezterm.exe', 'wezterm-gui.exe', 'wezterm-mux-server.exe', 'strip-ansi-escapes.exe')
$payload = $ownExecutables + @('OpenConsole.exe', 'conpty.dll', 'libEGL.dll', 'libGLESv2.dll', 'mesa\opengl32.dll')
foreach ($file in $payload) {
    $source = Join-Path $binaryRoot $file
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Missing $source. Run scripts\build-release.ps1 first."
    }
    Assert-X64Executable $source
}
$versionOutput = & (Join-Path $binaryRoot 'wezterm.exe') --version
if ($LASTEXITCODE -ne 0 -or "$versionOutput" -notmatch '^wezterm ([0-9][0-9A-Za-z.+_-]*)$') {
    throw 'Could not read a usable version from wezterm.exe --version.'
}
$version = $Matches[1]
$iscc = Resolve-Tool $IsccPath 'ISCC.exe' @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)
$signHelper = Join-Path $PSScriptRoot 'sign-windows.ps1'
$powerShellExe = (Get-Process -Id $PID).Path
if ($Sign) {
    if ([string]::IsNullOrWhiteSpace($env:CODESIGN_CERT)) {
        throw '-Sign requires CODESIGN_CERT (certificate subject in Cert:\CurrentUser\My).'
    }
    $certificates = @(Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object {
        $_.HasPrivateKey -and $_.NotBefore -le (Get-Date) -and $_.NotAfter -gt (Get-Date) -and
        $_.Subject.IndexOf($env:CODESIGN_CERT, [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
    if ($certificates.Count -eq 0) { throw 'No valid code-signing certificate with a private key matches CODESIGN_CERT.' }
    $sdkTools = @(Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
        Sort-Object { [version]$_.Directory.Parent.Name } -Descending | Select-Object -ExpandProperty FullName)
    $SignToolPath = Resolve-Tool $SignToolPath 'signtool.exe' $sdkTools
}

# A unique directory retains failed runs for diagnosis and avoids stale payloads.
$runRoot = Join-Path $outputRoot ('work\' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $runRoot 'stage'
$compiledOutput = Join-Path $runRoot 'output'
New-Item -ItemType Directory -Path (Join-Path $stage 'mesa'), $compiledOutput -Force | Out-Null
foreach ($file in $payload) {
    Copy-Item -LiteralPath (Join-Path $binaryRoot $file) -Destination (Join-Path $stage $file)
}
if ($Sign) {
    foreach ($file in $ownExecutables) {
        & $powerShellExe -NoProfile -ExecutionPolicy Bypass -File $signHelper `
            -FilePath (Join-Path $stage $file) -SignToolPath $SignToolPath -TimestampUrl $TimestampUrl
        if ($LASTEXITCODE -ne 0) { throw "Signing failed for $file." }
    }
    # This Microsoft binary already carries its publisher's signature.
    if ((Get-AuthenticodeSignature -LiteralPath (Join-Path $stage 'OpenConsole.exe')).Status -ne 'Valid') {
        throw 'The bundled Microsoft OpenConsole.exe must have a valid publisher signature.'
    }
}

$baseName = "WezTerm-$version-x64-setup"
$isccArguments = @("/DMyAppVersion=$version", "/DWezTermSourceDir=$stage", "/O$compiledOutput", "/F$baseName")
if ($Sign) {
    $signCommandParts = @($powerShellExe, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $signHelper,
        '-SignToolPath', $SignToolPath, '-TimestampUrl', $TimestampUrl, '-FilePath')
    $signCommand = (($signCommandParts | ForEach-Object { Quote-InnoArgument $_ }) -join ' ') + ' $f'
    $isccArguments += @('/DWezTermSign', "/Sweztermsign=$signCommand")
}
$isccArguments += Join-Path $repoRoot 'ci\windows-installer.iss'
Write-Host "Creating WezTerm $version installer (signing: $Sign)"
& $iscc @isccArguments
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed (exit $LASTEXITCODE). Work directory: $runRoot" }
$compiledInstaller = Join-Path $compiledOutput "$baseName.exe"
if (-not (Test-Path -LiteralPath $compiledInstaller -PathType Leaf)) { throw 'Inno Setup did not produce an installer.' }
if ($Sign -and (Get-AuthenticodeSignature -LiteralPath $compiledInstaller).Status -ne 'Valid') {
    throw 'The generated installer does not have a valid signature.'
}
$installer = Join-Path $outputRoot "$baseName.exe"
Copy-Item -LiteralPath $compiledInstaller -Destination $installer -Force
$hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
Set-Content -LiteralPath "$installer.sha256" -Value "$hash  $baseName.exe" -Encoding Ascii
[pscustomobject]@{ Installer = $installer; Version = $version; Signed = [bool]$Sign; SHA256 = $hash; WorkDirectory = $runRoot }
