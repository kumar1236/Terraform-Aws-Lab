# Configure AWS's ECR credential helper for one registry and verify access.
# Run this once in each PowerShell window before docker push/pull.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com(\.cn)?$')]
    [string]$Registry,

    [string]$Profile = 'lab-admin',

    [ValidatePattern('^[a-z]{2}(-[a-z]+)+-[0-9]+$')]
    [string]$Region = 'ap-south-1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT') { throw 'This helper setup is for the Windows lab laptop.' }
if ($Registry -notmatch ('\.dkr\.ecr\.' + [regex]::Escape($Region) + '\.amazonaws\.com(\.cn)?$')) {
    throw 'The ECR registry region must match -Region.'
}
Get-Command docker.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1 | Out-Null
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskHelperVersion = '0.12.0'
$taskHelperHash = '1545d0c797ad7d539f0b85ef6c8702193a93764d537b01f93b55cefae994c9e1'
$taskHelperDirectory = Join-Path $taskRoot ('.cache\tools\ecr-login\' + $taskHelperVersion)
$taskHelperPath = Join-Path $taskHelperDirectory 'docker-credential-ecr-login.exe'
if (-not (Test-Path -LiteralPath $taskHelperPath)) {
    [IO.Directory]::CreateDirectory($taskHelperDirectory) | Out-Null
    $taskHelperUrl = 'https://amazon-ecr-credential-helper-releases.s3.us-east-2.amazonaws.com/' + $taskHelperVersion + '/windows-amd64/docker-credential-ecr-login.exe'
    Invoke-WebRequest -UseBasicParsing -Uri $taskHelperUrl -OutFile $taskHelperPath
}
if ((Get-FileHash -LiteralPath $taskHelperPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskHelperHash) {
    throw 'ECR credential helper checksum mismatch. The executable was not run.'
}

# These environment settings remain available to Docker in the current terminal.
$env:AWS_PROFILE = $Profile
$env:AWS_REGION = $Region
$env:AWS_ECR_DISABLE_CACHE = 'true'
if (($env:PATH -split [IO.Path]::PathSeparator) -notcontains $taskHelperDirectory) {
    $env:PATH = $taskHelperDirectory + [IO.Path]::PathSeparator + $env:PATH
}

$taskProcess = $null
$taskCredentialsJson = $null
$taskCredentials = $null
$taskClient = $null
$taskResponse = $null
$taskAuthBytes = $null
try {
    $taskProcess = New-Object System.Diagnostics.Process
    $taskProcess.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $taskProcess.StartInfo.FileName = $taskHelperPath
    $taskProcess.StartInfo.Arguments = 'get'
    $taskProcess.StartInfo.UseShellExecute = $false
    $taskProcess.StartInfo.CreateNoWindow = $true
    $taskProcess.StartInfo.RedirectStandardInput = $true
    $taskProcess.StartInfo.RedirectStandardOutput = $true
    $taskProcess.StartInfo.RedirectStandardError = $true

    # .NET Framework creates and auto-flushes its stdin writer during Start().
    # Choose BOM-free encoding before startup, even though we write raw bytes later.
    $taskStdinEncoding = New-Object System.Text.UTF8Encoding($false)
    if ($null -ne [System.Diagnostics.ProcessStartInfo].GetProperty('StandardInputEncoding')) {
        $taskProcess.StartInfo.StandardInputEncoding = $taskStdinEncoding
        $taskProcess.Start() | Out-Null
    } else {
        $taskOriginalInputEncoding = [Console]::InputEncoding
        try {
            [Console]::InputEncoding = $taskStdinEncoding
            $taskProcess.Start() | Out-Null
        }
        finally {
            [Console]::InputEncoding = $taskOriginalInputEncoding
        }
    }
    $taskStdoutTask = $taskProcess.StandardOutput.ReadToEndAsync()
    $taskStderrTask = $taskProcess.StandardError.ReadToEndAsync()
    $taskRegistryBytes = [Text.Encoding]::UTF8.GetBytes($Registry + "`n")
    $taskProcess.StandardInput.BaseStream.Write($taskRegistryBytes, 0, $taskRegistryBytes.Length)
    $taskProcess.StandardInput.Close()
    if (-not $taskProcess.WaitForExit(45000)) {
        $taskProcess.Kill()
        throw 'ECR credential retrieval timed out after 45 seconds.'
    }
    $taskCredentialsJson = $taskStdoutTask.GetAwaiter().GetResult()
    # Consume stderr without printing it or the credential JSON.
    $taskStderrTask.GetAwaiter().GetResult() | Out-Null
    if ($taskProcess.ExitCode -ne 0) {
        $taskLogPath = Join-Path $env:USERPROFILE '.ecr\log\ecr-login.log'
        $taskReason = 'The ECR helper failed to retrieve credentials.'
        if (Test-Path -LiteralPath $taskLogPath) {
            $taskLastError = Get-Content -LiteralPath $taskLogPath -Tail 40 |
                Where-Object { $_ -match 'level=error|level=fatal' } |
                Select-Object -Last 1
            # Classify known errors without displaying log contents or credentials.
            if ($taskLastError -match 'Error parsing the serverURL') {
                $taskReason = 'The ECR helper rejected the registry address; check its input encoding.'
            } elseif ($taskLastError -match 'AccessDenied|not authorized') {
                $taskReason = 'AWS denied the ECR request; check the selected profile permissions.'
            } elseif ($taskLastError -match 'expired|invalid_grant') {
                $taskReason = 'The AWS login has expired; sign in again with aws login --profile ' + $Profile + '.'
            }
        }
        throw ($taskReason + " Profile: $Profile. Diagnostic log: $taskLogPath")
    }
    $taskCredentials = $taskCredentialsJson | ConvertFrom-Json
    if ($taskCredentials.Username -ne 'AWS' -or [string]::IsNullOrWhiteSpace($taskCredentials.Secret)) {
        throw 'Unexpected ECR credential response. Its contents were not displayed.'
    }

    # Check the registry over HTTPS without saving the token in Windows Credential Manager.
    Add-Type -AssemblyName System.Net.Http
    $taskClient = New-Object System.Net.Http.HttpClient
    $taskClient.Timeout = [TimeSpan]::FromSeconds(30)
    $taskAuthBytes = [Text.Encoding]::UTF8.GetBytes('AWS:' + $taskCredentials.Secret)
    $taskClient.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new(
        'Basic', [Convert]::ToBase64String($taskAuthBytes)
    )
    $taskResponse = $taskClient.GetAsync('https://' + $Registry + '/v2/').GetAwaiter().GetResult()
    if (-not $taskResponse.IsSuccessStatusCode) {
        throw ('ECR registry authentication returned HTTP ' + [int]$taskResponse.StatusCode + '.')
    }
    Write-Output ('Verified ECR authentication: HTTP ' + [int]$taskResponse.StatusCode)

    # Merge one registry-specific setting. Keep other auths, helpers and global credsStore.
    $taskDockerDirectory = if ($env:DOCKER_CONFIG) { $env:DOCKER_CONFIG } else { Join-Path $env:USERPROFILE '.docker' }
    $taskConfigPath = Join-Path $taskDockerDirectory 'config.json'
    if (Test-Path -LiteralPath $taskConfigPath) {
        $taskConfig = [IO.File]::ReadAllText($taskConfigPath) | ConvertFrom-Json
    } else {
        $taskConfig = [PSCustomObject]@{}
    }
    if (-not $taskConfig.PSObject.Properties['credHelpers'] -or $null -eq $taskConfig.credHelpers) {
        $taskConfig | Add-Member -NotePropertyName credHelpers -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    $taskExistingHelper = $taskConfig.credHelpers.PSObject.Properties[$Registry]
    if ($null -eq $taskExistingHelper -or $taskExistingHelper.Value -ne 'ecr-login') {
        $taskConfig.credHelpers | Add-Member -NotePropertyName $Registry -NotePropertyValue 'ecr-login' -Force
        [IO.Directory]::CreateDirectory($taskDockerDirectory) | Out-Null
        $taskEncoding = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($taskConfigPath, ($taskConfig | ConvertTo-Json -Depth 100) + [Environment]::NewLine, $taskEncoding)
    }
    Write-Output "Configured AWS ECR credential helper for $Registry"
    Write-Output 'Run docker push in this terminal. No docker login is required; ECR token-file caching is disabled.'
}
finally {
    if ($null -ne $taskAuthBytes) { [Array]::Clear($taskAuthBytes, 0, $taskAuthBytes.Length) }
    $taskCredentialsJson = $null
    $taskCredentials = $null
    if ($null -ne $taskResponse) { $taskResponse.Dispose() }
    if ($null -ne $taskClient) { $taskClient.Dispose() }
    if ($null -ne $taskProcess) { $taskProcess.Dispose() }
}
