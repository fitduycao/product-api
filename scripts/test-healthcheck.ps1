param([string]$BaseUrl = 'http://127.0.0.1:3000')

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Path $PSScriptRoot -Parent
$script:passed = 0
$restoreMongo = $false

function Assert-Check {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:passed++
    Write-Output "PASS: $Message"
}

function Read-Health {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/health" -TimeoutSec 8 -ErrorAction Stop
        return @{ Status = [int]$response.StatusCode; Body = ($response.Content | ConvertFrom-Json) }
    } catch {
        if ($null -ne $_.Exception.Response) {
            return @{ Status = [int]$_.Exception.Response.StatusCode; Body = $null }
        }
        throw
    }
}

function Get-HealthStatus {
    param([string]$Container)
    $status = & docker inspect $Container --format '{{.State.Health.Status}}'
    if ($LASTEXITCODE -ne 0) { throw "Cannot inspect $Container health." }
    return $status
}

Push-Location -LiteralPath $projectRoot
try {
    Assert-Check ((Get-HealthStatus 'nammongodb') -eq 'healthy') 'MongoDB starts healthy'
    Assert-Check ((Get-HealthStatus 'product-api') -eq 'healthy') 'Product API starts healthy'
    $response = Read-Health
    Assert-Check ($response.Status -eq 200 -and $response.Body.mongodb -eq 'connected') 'GET /health confirms a successful MongoDB ping'

    & docker compose exec -T api node src/healthcheck.js
    Assert-Check ($LASTEXITCODE -eq 0) 'API probe exits with code 0 while MongoDB is available'

    try {
        $restoreMongo = $true
        & docker compose stop mongodb
        if ($LASTEXITCODE -ne 0) { throw 'Cannot temporarily stop MongoDB for the outage test.' }

        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Read-Health
        $timer.Stop()
        Assert-Check ($response.Status -eq 503) 'GET /health returns 503 while MongoDB is stopped'
        Assert-Check ($timer.ElapsedMilliseconds -lt 5000) 'Unavailable database is detected within 5 seconds'

        $unhealthy = $false
        for ($attempt = 0; $attempt -lt 30; $attempt++) {
            if ((Get-HealthStatus 'product-api') -eq 'unhealthy') { $unhealthy = $true; break }
            Start-Sleep -Seconds 2
        }
        Assert-Check $unhealthy 'Docker marks Product API unhealthy when MongoDB is unavailable'
    } finally {
        if ($restoreMongo) {
            & docker compose start --wait --wait-timeout 120 mongodb
            if ($LASTEXITCODE -ne 0) { throw 'MongoDB/API did not recover after the outage test.' }
            # An existing unhealthy API needs time for Mongoose to reconnect.
            # compose up --wait may reject that initial unhealthy state immediately.
            $apiRecovered = $false
            for ($attempt = 0; $attempt -lt 30; $attempt++) {
                if ((Get-HealthStatus 'product-api') -eq 'healthy') { $apiRecovered = $true; break }
                Start-Sleep -Seconds 2
            }
            if (-not $apiRecovered) { throw 'Product API did not return to healthy after MongoDB recovered.' }
        }
    }

    $response = Read-Health
    Assert-Check ($response.Status -eq 200 -and $response.Body.mongodb -eq 'connected') 'GET /health returns 200 after MongoDB recovers'
    Assert-Check ((Get-HealthStatus 'nammongodb') -eq 'healthy' -and (Get-HealthStatus 'product-api') -eq 'healthy') 'Both containers recover to healthy'
    Write-Output "Healthcheck checks passed: $script:passed"
} finally {
    Pop-Location
}
