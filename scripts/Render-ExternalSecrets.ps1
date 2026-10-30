# Downloads a pinned chart, verifies SHA256, and renders YAML without deploying.
[CmdletBinding()]
param([string]$OutputFile)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskPin = Get-Content -Raw -LiteralPath (Join-Path $taskRoot 'platform\external-secrets-chart.json') | ConvertFrom-Json
$taskCache = Join-Path $taskRoot '.cache\helm'
[IO.Directory]::CreateDirectory($taskCache) | Out-Null
$taskArchive = Join-Path $taskCache ("external-secrets-" + $taskPin.version + '.tgz')
if (-not (Test-Path -LiteralPath $taskArchive)) {
    & helm pull $taskPin.name --repo $taskPin.repository --version $taskPin.version --destination $taskCache
    if ($LASTEXITCODE -ne 0) { throw 'Could not download the pinned ESO chart.' }
}
$taskActualHash = (Get-FileHash -LiteralPath $taskArchive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($taskActualHash -ne $taskPin.sha256) { throw 'ESO archive checksum mismatch; do not use this package.' }
if (-not $OutputFile) { $OutputFile = Join-Path $taskRoot 'rendered\external-secrets.yaml' }
$taskOutput = [IO.Path]::GetFullPath($OutputFile)
$taskValues = Join-Path $taskRoot 'platform\external-secrets-values.yaml'
$taskYaml = @(& helm template external-secrets $taskArchive --namespace external-secrets --kube-version 1.36.0 --include-crds --values $taskValues)
if ($LASTEXITCODE -ne 0) { throw 'ESO rendering failed; rendered file was not changed.' }
if ($taskYaml.Count -eq 0) { throw 'ESO rendering produced no resources.' }
[IO.Directory]::CreateDirectory((Split-Path -Parent $taskOutput)) | Out-Null
$taskEncoding = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($taskOutput, ($taskYaml -join "`n") + "`n", $taskEncoding)
Write-Output "Verified ESO chart $($taskPin.version); rendered: $taskOutput"
