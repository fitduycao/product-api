param(
    [Parameter(Mandatory = $true)][ValidatePattern('^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/?$')][string]$RepositoryUrl,
    [string]$RunnerDirectory = 'D:\actions-runner-product-api',
    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'
$runnerRoot = [IO.Path]::GetFullPath($RunnerDirectory)
if (Test-Path -LiteralPath (Join-Path $runnerRoot '.runner')) {
    throw 'Runner is already registered. Inspect its repository before configuring again.'
}
$configPath = Join-Path $runnerRoot 'config.cmd'
if (-not (Test-Path -LiteralPath $configPath)) {
    if ((Test-Path -LiteralPath $runnerRoot) -and @(Get-ChildItem -LiteralPath $runnerRoot -Force).Count -gt 0) {
        throw 'Runner directory is not empty. Choose a new directory; no files were replaced.'
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/actions/runner/releases/latest' -Headers @{ 'User-Agent' = 'product-api-local-runner-setup' }
    $asset = @($release.assets | Where-Object { $_.name -match '^actions-runner-win-x64-[0-9.]+\.zip$' })
    if ($asset.Count -ne 1 -or $asset[0].digest -notmatch '^sha256:[0-9a-f]{64}$') {
        throw 'Cannot determine the official Windows x64 runner and SHA256. Use the download commands shown by GitHub Settings > Actions > Runners.'
    }
    New-Item -ItemType Directory -Path $runnerRoot -Force | Out-Null
    $archivePath = Join-Path $runnerRoot $asset[0].name
    try {
        Invoke-WebRequest -Uri $asset[0].browser_download_url -OutFile $archivePath -UseBasicParsing
        $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $asset[0].digest.Substring(7)) { throw 'Runner archive SHA256 mismatch.' }
        Expand-Archive -LiteralPath $archivePath -DestinationPath $runnerRoot
        Write-Output "Prepared official runner $($release.tag_name) at $runnerRoot (SHA256 verified)."
    } finally {
        if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath }
    }
}
if ($PrepareOnly) {
    Write-Output 'Package prepared only; registration and run.cmd are still required.'
    return
}

Write-Output 'Get a fresh registration token from the target GitHub repository: Settings > Actions > Runners > New self-hosted runner > Windows x64.'
$secureToken = Read-Host 'Paste the one-hour RUNNER REGISTRATION token (not Docker Hub PAT)' -AsSecureString
$tokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
Push-Location -LiteralPath $runnerRoot
try {
    $registrationToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPointer)
    & $configPath --url $RepositoryUrl.TrimEnd('/') --token $registrationToken --name ($env:COMPUTERNAME + '-product-api') --labels product-api-local --work _work --unattended
    if ($LASTEXITCODE -ne 0) { throw 'Runner registration failed. Verify repository URL, admin access and token expiry.' }
} finally {
    $registrationToken = $null
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPointer)
    $secureToken.Dispose()
    Pop-Location
}
Write-Output "Registered. Start under the Windows user who can access Docker Desktop: & '$runnerRoot\run.cmd'"
