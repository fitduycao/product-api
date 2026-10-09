param(
    [string]$BaseUrl = 'http://127.0.0.1:3000'
)

$ErrorActionPreference = 'Stop'
$pidValue = 'TEST-DOCKER-' + [guid]::NewGuid().ToString('N')
$productUrl = "$BaseUrl/api/products/$pidValue"
$script:passed = 0
$created = $false

function Send-ApiRequest {
    param([string]$Method, [string]$Url, [object]$Body)
    $arguments = @{
        Method = $Method
        Uri = $Url
        UseBasicParsing = $true
        TimeoutSec = 15
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $arguments.ContentType = 'application/json'
        $arguments.Body = $Body | ConvertTo-Json -Depth 5 -Compress
    }
    try {
        $response = Invoke-WebRequest @arguments
        return @{
            Status = [int]$response.StatusCode
            Data = $response.Content | ConvertFrom-Json
        }
    } catch {
        if ($null -ne $_.Exception.Response) {
            return @{ Status = [int]$_.Exception.Response.StatusCode; Data = $null }
        }
        throw
    }
}

function Assert-Check {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:passed++
    Write-Output "PASS: $Message"
}

try {
    $health = Send-ApiRequest -Method Get -Url "$BaseUrl/health"
    Assert-Check ($health.Status -eq 200 -and $health.Data.mongodb -eq 'connected') 'Container API connected to MongoDB'

    $product = @{ pid = $pidValue; pname = 'Docker keyboard'; price = 350000; quantity = 10 }
    $result = Send-ApiRequest -Method Post -Url "$BaseUrl/api/products" -Body $product
    Assert-Check ($result.Status -eq 201 -and $result.Data.pid -eq $pidValue) 'POST creates Product'
    $created = $true

    $storedPid = & docker exec nammongodb mongosh productdb --quiet --eval "db.products.findOne({pid:'$pidValue'}).pid"
    if ($LASTEXITCODE -ne 0) { throw 'Cannot verify stored Product in nammongodb.' }
    Assert-Check (($storedPid | Out-String).Trim() -eq $pidValue) 'Product is stored in nammongodb/productdb'

    $result = Send-ApiRequest -Method Get -Url "$BaseUrl/api/products"
    Assert-Check ($result.Status -eq 200 -and @($result.Data | Where-Object { $_.pid -eq $pidValue }).Count -eq 1) 'GET lists Product'

    $result = Send-ApiRequest -Method Get -Url $productUrl
    Assert-Check ($result.Status -eq 200 -and $result.Data.quantity -eq 10) 'GET finds Product by pid'

    $result = Send-ApiRequest -Method Post -Url "$BaseUrl/api/products" -Body $product
    Assert-Check ($result.Status -eq 409) 'Duplicate pid returns 409'

    $updated = @{ pid = $pidValue; pname = 'Docker mechanical keyboard'; price = 500000; quantity = 8 }
    $result = Send-ApiRequest -Method Put -Url $productUrl -Body $updated
    Assert-Check ($result.Status -eq 200 -and $result.Data.price -eq 500000) 'PUT updates Product'

    $result = Send-ApiRequest -Method Patch -Url $productUrl -Body @{ quantity = 5 }
    Assert-Check ($result.Status -eq 200 -and $result.Data.quantity -eq 5) 'PATCH updates quantity'

    $result = Send-ApiRequest -Method Patch -Url $productUrl -Body @{ price = -1 }
    Assert-Check ($result.Status -eq 400) 'Negative price returns 400'

    $result = Send-ApiRequest -Method Get -Url $productUrl
    Assert-Check ($result.Data.price -eq 500000 -and $result.Data.quantity -eq 5) 'Rejected update preserves stored data'

    $result = Send-ApiRequest -Method Delete -Url $productUrl
    Assert-Check ($result.Status -eq 200) 'DELETE removes Product'
    $created = $false

    $result = Send-ApiRequest -Method Get -Url $productUrl
    Assert-Check ($result.Status -eq 404) 'Deleted Product returns 404'

    Write-Output "Docker API checks passed: $script:passed"
} finally {
    if ($created) {
        $null = Send-ApiRequest -Method Delete -Url $productUrl
    }
}
