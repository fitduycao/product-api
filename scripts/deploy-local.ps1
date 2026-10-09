param(
    [Parameter(Mandatory = $true)][string]$DeploymentPath,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9][a-z0-9./:_-]+$')][string]$DockerHubImage,
    [Parameter(Mandatory = $true)][ValidatePattern('^sha-[0-9a-f]{40}$')][string]$ImageTag,
    [string]$ComposeFile,
    [ValidatePattern('^[a-z0-9][a-z0-9_-]*$')][string]$ProjectName = 'product-api',
    [ValidateRange(10, 300)][int]$HealthTimeoutSeconds = 180,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
if (-not $ComposeFile) { $ComposeFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'docker-compose-prod.yaml' }

function Invoke-Docker {
    param([string[]]$DockerArguments)
    $result = & docker @DockerArguments
    if ($LASTEXITCODE -ne 0) { throw "Docker command failed: $($DockerArguments[0]) $($DockerArguments[1]) (exit $LASTEXITCODE)." }
    return $result
}

function Write-AtomicText {
    param([string]$Path, [string]$Content)
    $temporaryPath = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $backupPath = $Path + '.' + [guid]::NewGuid().ToString('N') + '.backup'
    try {
        [IO.File]::WriteAllText($temporaryPath, $Content, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporaryPath, $Path, $backupPath) }
        else { [IO.File]::Move($temporaryPath, $Path) }
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath }
        if (Test-Path -LiteralPath $backupPath) { Remove-Item -LiteralPath $backupPath }
    }
}

$deploymentRoot = (Resolve-Path -LiteralPath $DeploymentPath).Path
$sourceCompose = (Resolve-Path -LiteralPath $ComposeFile).Path
$envPath = Join-Path $deploymentRoot '.env.prod'
$deployedComposePath = Join-Path $deploymentRoot 'docker-compose-prod.yaml'
if (-not (Test-Path -LiteralPath $envPath)) { throw "Create and configure $envPath before deployment." }
$previousEnvText = [IO.File]::ReadAllText($envPath)
$previousComposeText = $null
if (Test-Path -LiteralPath $deployedComposePath) { $previousComposeText = [IO.File]::ReadAllText($deployedComposePath) }
$sourceComposeText = [IO.File]::ReadAllText($sourceCompose)
$previousImageSetting = [Environment]::GetEnvironmentVariable('DOCKERHUB_IMAGE', 'Process')
$previousTagSetting = [Environment]::GetEnvironmentVariable('IMAGE_TAG', 'Process')
$rollbackOverridePath = Join-Path $deploymentRoot ('.rollback-' + [guid]::NewGuid().ToString('N') + '.yaml')
$rollbackTag = $ProjectName + '-rollback:previous'
$previousApiImage = $null
$apiChanged = $false
$settingsChanged = $false

try {
    [Environment]::SetEnvironmentVariable('DOCKERHUB_IMAGE', $DockerHubImage, 'Process')
    [Environment]::SetEnvironmentVariable('IMAGE_TAG', $ImageTag, 'Process')
    $composeArguments = @('--project-directory', $deploymentRoot, '--project-name', $ProjectName, '--env-file', $envPath, '-f', $sourceCompose)
    $engineType = Invoke-Docker @('info', '--format', '{{.OSType}}')
    if ($engineType -ne 'linux') { throw 'Docker Engine must be running Linux containers.' }
    $config = (Invoke-Docker (@('compose') + $composeArguments + @('config', '--format', 'json')) | Out-String) | ConvertFrom-Json
    if ($config.services.api.PSObject.Properties.Name -contains 'build') { throw 'Deployment must use the registry image, without build.' }
    if ($config.services.api.image -ne ($DockerHubImage + ':' + $ImageTag)) { throw 'Compose image does not match the published commit.' }
    if (-not $config.services.api.healthcheck.test -or -not $config.services.mongodb.healthcheck.test -or $config.services.api.depends_on.mongodb.condition -ne 'service_healthy') {
        throw 'MongoDB and API healthchecks are required.'
    }
    if (-not $config.volumes.mongodb_data.external) { throw 'The production MongoDB volume must be external.' }
    $volumeName = $config.volumes.mongodb_data.name
    $apiPort = @($config.services.api.ports | Where-Object { $_.host_ip -eq '127.0.0.1' -and $_.target -eq [int]$config.services.api.environment.PORT })
    if ($apiPort.Count -ne 1) { throw 'Expose exactly one API port on 127.0.0.1.' }
    $healthUrl = 'http://127.0.0.1:' + $apiPort[0].published + '/health'

    # Refuse to replace containers belonging to a different project or manual setup.
    foreach ($serviceName in @('mongodb', 'api')) {
        $containerName = $config.services.$serviceName.container_name
        if (-not $containerName) { throw 'Explicit production container names are required.' }
        $containerId = Invoke-Docker @('ps', '-aq', '--filter', "name=^/$containerName`$")
        if ($containerId) {
            $info = ((Invoke-Docker @('inspect', $containerId) | Out-String) | ConvertFrom-Json)[0]
            if ($info.Config.Labels.'com.docker.compose.project' -ne $ProjectName -or $info.Config.Labels.'com.docker.compose.service' -ne $serviceName) {
                throw "Container $containerName belongs to another project or was created manually."
            }
            if ($serviceName -eq 'api') { $previousApiImage = $info.Image }
            if ($serviceName -eq 'mongodb') {
                $mount = @($info.Mounts | Where-Object { $_.Destination -eq '/data/db' -and $_.Name -eq $volumeName })
                if ($mount.Count -ne 1) { throw 'Existing MongoDB uses a different data volume.' }
            }
        }
    }
    Write-Output "Preflight OK: $ProjectName -> ${DockerHubImage}:$ImageTag"
    if ($CheckOnly) { return }

    # Pull before changing any running service. A missing tag leaves the old API running.
    Invoke-Docker (@('compose') + $composeArguments + @('pull', 'api'))
    $volumes = Invoke-Docker @('volume', 'ls', '--format', '{{.Name}}')
    if ($volumes -notcontains $volumeName) { Invoke-Docker @('volume', 'create', $volumeName) }
    if ($previousApiImage) { Invoke-Docker @('tag', $previousApiImage, $rollbackTag) }
    Invoke-Docker (@('compose') + $composeArguments + @('up', '-d', '--no-build', '--wait', '--wait-timeout', "$HealthTimeoutSeconds", 'mongodb'))
    $apiChanged = $true
    Invoke-Docker (@('compose') + $composeArguments + @('up', '-d', '--no-build', '--no-deps', '--pull', 'never', '--wait', '--wait-timeout', "$HealthTimeoutSeconds", 'api'))
    $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 10
    if ($health.status -ne 'ok' -or $health.mongodb -ne 'connected') { throw 'Deployed API cannot confirm its MongoDB connection.' }

    # Persist the successful release for subsequent manual Compose commands.
    $newEnvText = [regex]::Replace($previousEnvText, '(?m)^(DOCKERHUB_IMAGE|IMAGE_TAG)=.*\r?\n?', '')
    $newEnvText = $newEnvText.TrimEnd() + "`nDOCKERHUB_IMAGE=$DockerHubImage`nIMAGE_TAG=$ImageTag`n"
    $settingsChanged = $true
    Write-AtomicText -Path $envPath -Content $newEnvText
    if ($sourceComposeText -ne $previousComposeText) { Write-AtomicText -Path $deployedComposePath -Content $sourceComposeText }
    Invoke-Docker (@('compose') + $composeArguments + @('ps'))
    Write-Output "Deployment healthy: ${DockerHubImage}:$ImageTag -> $healthUrl"
    if ($env:GITHUB_STEP_SUMMARY) {
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value "Local deployment healthy: ${DockerHubImage}:$ImageTag ($healthUrl)"
    }
} catch {
    $deploymentError = $_
    if ($apiChanged) {
        & docker compose @composeArguments ps -a
        & docker compose @composeArguments logs --no-color --tail 40 api
        try {
            if ($previousApiImage) {
                $rollbackConfig = @{ services = @{ api = @{ image = $rollbackTag; pull_policy = 'never' } } } | ConvertTo-Json -Depth 5
                [IO.File]::WriteAllText($rollbackOverridePath, $rollbackConfig, [Text.UTF8Encoding]::new($false))
                Invoke-Docker (@('compose') + $composeArguments + @('-f', $rollbackOverridePath, 'up', '-d', '--no-build', '--no-deps', '--pull', 'never', '--wait', '--wait-timeout', "$HealthTimeoutSeconds", 'api'))
                $restoredHealth = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 10
                if ($restoredHealth.status -ne 'ok' -or $restoredHealth.mongodb -ne 'connected') { throw 'Rollback healthcheck failed.' }
                Write-Warning 'Deployment failed; previous API image has been restored and is healthy.'
            } else {
                Invoke-Docker (@('compose') + $composeArguments + @('stop', 'api'))
                Write-Warning 'First deployment failed; stopped the failed API. MongoDB data is retained.'
            }
        } catch { Write-Warning "Rollback/stop failed: $($_.Exception.Message)" }
    }
    if ($settingsChanged) {
        Write-AtomicText -Path $envPath -Content $previousEnvText
        if ($null -ne $previousComposeText) { Write-AtomicText -Path $deployedComposePath -Content $previousComposeText }
    }
    throw $deploymentError
} finally {
    if (Test-Path -LiteralPath $rollbackOverridePath) { Remove-Item -LiteralPath $rollbackOverridePath }
    [Environment]::SetEnvironmentVariable('DOCKERHUB_IMAGE', $previousImageSetting, 'Process')
    [Environment]::SetEnvironmentVariable('IMAGE_TAG', $previousTagSetting, 'Process')
}
