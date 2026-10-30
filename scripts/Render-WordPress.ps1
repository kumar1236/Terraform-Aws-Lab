# This script only lints/renders local YAML. It does not contact AWS or EKS.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ImageRepository,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ImageTag,

    [ValidatePattern('^[a-z0-9]([a-z0-9-]*[a-z0-9])?$')]
    [ValidateLength(1, 53)]
    [string]$ReleaseName = 'wordpress',

    [ValidatePattern('^[a-z0-9]([a-z0-9-]*[a-z0-9])?$')]
    [ValidateLength(1, 63)]
    [string]$Namespace = 'wordpress',

    [string]$ValuesFile,

    [string]$OutputFile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskChart = Join-Path $taskRoot 'charts\wordpress'
if (-not $OutputFile) { $OutputFile = Join-Path $taskRoot 'rendered\wordpress.yaml' }
$taskOutput = [IO.Path]::GetFullPath($OutputFile)
$taskOverrides = @('--set-string', "image.repository=$ImageRepository", '--set-string', "image.tag=$ImageTag")
if ($ValuesFile) {
    $taskOverrides += @('--values', (Resolve-Path -LiteralPath $ValuesFile).Path)
}
$taskCommon = @('--namespace', $Namespace, '--kube-version', '1.36.0') + $taskOverrides
& helm lint $taskChart --strict @taskCommon
if ($LASTEXITCODE -ne 0) { throw 'Helm lint failed; rendered file was not changed.' }
$taskYaml = @(& helm template $ReleaseName $taskChart @taskCommon)
if ($LASTEXITCODE -ne 0) { throw 'Helm rendering failed; rendered file was not changed.' }
if ($taskYaml.Count -eq 0) { throw 'Helm produced no resources.' }
[IO.Directory]::CreateDirectory((Split-Path -Parent $taskOutput)) | Out-Null
$taskEncoding = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($taskOutput, ($taskYaml -join "`n") + "`n", $taskEncoding)
Write-Output "Rendered WordPress manifests: $taskOutput"
