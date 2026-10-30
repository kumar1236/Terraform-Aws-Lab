# Run once after Terraform apply. Generates passwords without displaying them.
# This does not rotate passwords in an existing MariaDB database.
[CmdletBinding()]
param(
    [string]$SecretId = 'wp-lab/wordpress/database',
    [string]$Profile = 'lab-admin',
    [string]$Region = 'ap-south-1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT') { throw 'This initializer uses Windows ACLs; run it from your Windows laptop.' }
$taskAwsArgs = @('--profile', $Profile, '--region', $Region)
$taskMetadataJson = @(& aws secretsmanager describe-secret --secret-id $SecretId @taskAwsArgs --output json)
if ($LASTEXITCODE -ne 0) { throw 'Secret metadata could not be read. Apply Terraform first and check your AWS profile.' }
$taskMetadata = ($taskMetadataJson -join "`n") | ConvertFrom-Json
$taskVersionMap = $taskMetadata.PSObject.Properties['VersionIdsToStages']
if ($null -ne $taskVersionMap -and @($taskVersionMap.Value.PSObject.Properties).Count -gt 0) {
    throw 'This secret already has a value. Initialization refused; database password rotation is a separate operation.'
}

$taskTempDirectory = Join-Path ([IO.Path]::GetTempPath()) ('wp-lab-secret-' + [Guid]::NewGuid().ToString('N'))
$taskSecretFile = Join-Path $taskTempDirectory 'secret.json'
$taskRng = [Security.Cryptography.RandomNumberGenerator]::Create()
try {
    [IO.Directory]::CreateDirectory($taskTempDirectory) | Out-Null
    $taskIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $taskAcl = New-Object Security.AccessControl.DirectorySecurity
    $taskAcl.SetAccessRuleProtection($true, $false)
    $taskAcl.SetOwner($taskIdentity)
    $taskRule = [Security.AccessControl.FileSystemAccessRule]::new(
        $taskIdentity,
        [Security.AccessControl.FileSystemRights]::FullControl,
        ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),
        [Security.AccessControl.PropagationFlags]::None,
        [Security.AccessControl.AccessControlType]::Allow
    )
    $taskAcl.AddAccessRule($taskRule)
    Set-Acl -LiteralPath $taskTempDirectory -AclObject $taskAcl

    $taskRootBytes = New-Object byte[] 32
    $taskAppBytes = New-Object byte[] 32
    $taskRng.GetBytes($taskRootBytes)
    $taskRng.GetBytes($taskAppBytes)
    $taskSecretValue = @{
        'root-password' = [Convert]::ToBase64String($taskRootBytes)
        'wordpress-password' = [Convert]::ToBase64String($taskAppBytes)
    } | ConvertTo-Json -Compress
    $taskEncoding = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($taskSecretFile, $taskSecretValue, $taskEncoding)
    & aws secretsmanager put-secret-value --secret-id $SecretId --secret-string ("file://" + $taskSecretFile) @taskAwsArgs --query VersionId --output text
    if ($LASTEXITCODE -ne 0) { throw 'Writing the secret value failed.' }
    Write-Output 'Initialized database credentials in Secrets Manager. Passwords were not displayed.'
}
finally {
    $taskRng.Dispose()
    if ($null -ne (Get-Variable taskRootBytes -ErrorAction SilentlyContinue)) { [Array]::Clear($taskRootBytes, 0, $taskRootBytes.Length) }
    if ($null -ne (Get-Variable taskAppBytes -ErrorAction SilentlyContinue)) { [Array]::Clear($taskAppBytes, 0, $taskAppBytes.Length) }
    if (Test-Path -LiteralPath $taskSecretFile) { Remove-Item -LiteralPath $taskSecretFile -Force }
    if (Test-Path -LiteralPath $taskTempDirectory) { Remove-Item -LiteralPath $taskTempDirectory -Force }
}
