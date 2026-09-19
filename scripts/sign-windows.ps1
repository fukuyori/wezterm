#requires -Version 5.1
<#
.SYNOPSIS
Signs and verifies one file. Used by build-installer.ps1 and Inno Setup.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string]$SignToolPath,
    [Parameter(Mandatory)][string]$TimestampUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try {
    if ([string]::IsNullOrWhiteSpace($env:CODESIGN_CERT)) {
        throw 'Set CODESIGN_CERT to the subject name of your code-signing certificate.'
    }
    foreach ($path in @($FilePath, $SignToolPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "File not found: $path"
        }
    }
    $signArguments = @('sign', '/q', '/a', '/n', $env:CODESIGN_CERT,
        '/fd', 'SHA256', '/tr', $TimestampUrl, '/td', 'SHA256', $FilePath)
    & $SignToolPath @signArguments
    if ($LASTEXITCODE -ne 0) { throw "Code signing failed (exit $LASTEXITCODE)." }
    & $SignToolPath verify /q /pa /all /tw $FilePath
    if ($LASTEXITCODE -ne 0) { throw "Signature verification failed (exit $LASTEXITCODE)." }
    $signature = Get-AuthenticodeSignature -LiteralPath $FilePath
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.TimeStamperCertificate) {
        throw 'A valid, timestamped Authenticode signature is required.'
    }
    Write-Host "Signed and verified: $FilePath"
} catch {
    Write-Error -ErrorRecord $_ -ErrorAction Continue
    exit 1
}
