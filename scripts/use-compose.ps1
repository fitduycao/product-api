$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Path $PSScriptRoot -Parent

function Get-ContainerInfo {
    param([string]$Name)
    $containerId = & docker ps -a --filter "name=^/$Name$" --format '{{.ID}}'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot connect to Docker Engine.' }
    if (-not $containerId) { return $null }
    $details = & docker inspect $Name
    if ($LASTEXITCODE -ne 0) { throw "Cannot inspect $Name." }
    return ($details | ConvertFrom-Json)[0]
}

function Test-ComposeContainer {
    param([object]$Container, [string]$Service)
    return $null -ne $Container -and
        $Container.Config.Labels.'com.docker.compose.project' -eq 'product-api' -and
        $Container.Config.Labels.'com.docker.compose.service' -eq $Service
}

function Get-ProductSnapshotHash {
    $raw = $null
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        $raw = & docker exec nammongodb mongosh productdb --quiet --eval 'EJSON.stringify(db.products.find().sort({_id:1}).toArray())' 2>$null
        if ($LASTEXITCODE -eq 0) { break }
        Start-Sleep -Seconds 2
    }
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read Product documents for migration verification.' }
    $snapshot = ($raw | Out-String).Trim()
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($snapshot))).Replace('-', '')
    } finally {
        $hasher.Dispose()
    }
}

Push-Location -LiteralPath $projectRoot
try {
    & docker compose config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Invalid Compose configuration.' }

    $mongo = Get-ContainerInfo -Name 'nammongodb'
    $api = Get-ContainerInfo -Name 'product-api'
    $migrateMongo = $null -ne $mongo -and -not (Test-ComposeContainer -Container $mongo -Service 'mongodb')
    $migrateApi = $null -ne $api -and -not (Test-ComposeContainer -Container $api -Service 'api')

    # Verify the existing containers before changing their state or names.
    if ($migrateMongo) {
        if ($mongo.Config.Labels.'com.docker.compose.project') {
            throw 'nammongodb belongs to another Compose project; inspect it first.'
        }
        $dataMount = @($mongo.Mounts | Where-Object {
            $_.Destination -eq '/data/db' -and $_.Type -eq 'volume' -and $_.Name -eq 'nammongodb_data'
        })
        if ($dataMount.Count -ne 1 -or $mongo.Config.Image -notlike 'mongo:8.0*') {
            throw 'Existing nammongodb does not match the expected MongoDB 8.0 data volume.'
        }
        if (Get-ContainerInfo -Name 'nammongodb-before-compose') {
            throw 'Backup nammongodb-before-compose already exists; inspect it first.'
        }
    }

    if ($migrateApi) {
        if ($api.Config.Labels.'com.docker.compose.project' -or $api.Config.Image -ne 'product-api:1.0') {
            throw 'Existing product-api is not the manual container from exercise 7.'
        }
        if (Get-ContainerInfo -Name 'product-api-before-compose') {
            throw 'Backup product-api-before-compose already exists; inspect it first.'
        }
    }

    # Create only when absent; external volume remains outside Compose lifecycle.
    $volumeName = & docker volume ls --filter 'name=^nammongodb_data$' --format '{{.Name}}'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect MongoDB data volume.' }
    if (-not $volumeName) {
        & docker volume create nammongodb_data
        if ($LASTEXITCODE -ne 0) { throw 'Cannot create nammongodb_data.' }
    }

    # Build first so a build error does not interrupt the old application.
    & docker compose build api
    if ($LASTEXITCODE -ne 0) { throw 'Compose image build failed.' }

    # Verify that MongoDB can start before stopping or renaming the API.
    if ($null -ne $mongo -and $mongo.State.Status -ne 'running') {
        & docker start nammongodb
        if ($LASTEXITCODE -ne 0) {
            throw 'Cannot start MongoDB. Check the Windows process listening on port 27017 before continuing.'
        }
    }

    if ($migrateApi) {
        & docker stop --timeout 30 product-api
        if ($LASTEXITCODE -ne 0) { throw 'Cannot stop the old API.' }
        & docker rename product-api product-api-before-compose
        if ($LASTEXITCODE -ne 0) { throw 'Cannot preserve the old API container.' }
    }

    $previousDataHash = $null
    if ($null -ne $mongo) {
        $previousDataHash = Get-ProductSnapshotHash
    }

    if ($migrateMongo) {
        & docker stop --timeout 60 nammongodb
        if ($LASTEXITCODE -ne 0) { throw 'Cannot stop the old MongoDB.' }
        & docker rename nammongodb nammongodb-before-compose
        if ($LASTEXITCODE -ne 0) { throw 'Cannot preserve the old MongoDB container.' }
    }

    & docker compose up -d --wait --wait-timeout 180
    if ($LASTEXITCODE -ne 0) {
        & docker compose logs --tail 50
        throw 'Compose services did not become ready; inspect the logs and COMPOSE.md rollback instructions.'
    }

    & docker compose ps
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Compose services.' }

    if ($previousDataHash) {
        $currentDataHash = Get-ProductSnapshotHash
        if ($previousDataHash -ne $currentDataHash) {
            throw 'Product data changed during migration; inspect MongoDB before continuing.'
        }
        Write-Output 'PASS: Existing Product documents preserved across Compose migration'
    }

    & (Join-Path $PSScriptRoot 'test-docker-api.ps1')
    Write-Output 'Compose is ready: http://127.0.0.1:3000/health'
} finally {
    Pop-Location
}
