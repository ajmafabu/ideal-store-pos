$ErrorActionPreference = "Continue"
$SUPABASE_URL = "https://hrlciruepdstrvtsuoyr.supabase.co"
$API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhybGNpcnVlcGRzdHJ2dHN1b3lyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxMDA4MjgsImV4cCI6MjA5ODY3NjgyOH0.-FqYflyY-0333oNlC5clOpcOm_E60R6e9WULp_xZHEo"
$headers = @{ "apikey" = $API_KEY; "Authorization" = "Bearer $API_KEY"; "Content-Type" = "application/json" }
$filePath = "C:\Users\abuthahir\Documents\ideal_store\wholesale_market\products_list.json"
$dictPath = "C:\Users\abuthahir\Documents\ideal_store\wholesale_market\tamil_dict.json"
$allProducts = Get-Content $filePath -Raw -Encoding UTF8 | ConvertFrom-Json
$dict = Get-Content $dictPath -Raw -Encoding UTF8 | ConvertFrom-Json
$productsToUpdate = $allProducts | Where-Object { -not $_.tamil_name -or $_.tamil_name -eq "" }
Write-Host "Total: $($allProducts.Count) | To update: $($productsToUpdate.Count)" -ForegroundColor Cyan

$wm = @{}
foreach ($prop in $dict.PSObject.Properties) { $wm[$prop.Name] = $prop.Value }

function Get-TamilName {
    param([string]$name)
    $n = $name.ToLower().Trim()
    $n = $n -replace "[^a-z0-9\s]", ""
    $n = $n -replace "\s+", " "
    $sortedKeys = $wm.Keys | Sort-Object { $_.Length } -Descending
    foreach ($key in $sortedKeys) {
        if ($key.Contains(" ") -and $n.Contains($key)) {
            $n = $n.Replace($key, "|||$($wm[$key])|||")
        }
    }
    $words = $n -split '\s+'
    $out = @()
    foreach ($w in $words) {
        $cw = $w.Trim()
        if ($cw -eq "") { continue }
        if ($cw -match '^\|\|\|(.+)\|\|\|$') { $out += $matches[1]; continue }
        if ($cw -match '^\d+$') { $out += $cw; continue }
        if ($cw -match '^(\d+)\s*(rs|ra|r)$') { $out += "$($matches[1]) ரூபாய்"; continue }
        if ($cw -match '^(\d+)\s*g$') { $out += "$($matches[1]) கிராம்"; continue }
        if ($cw -match '^(\d+)\s*gm$') { $out += "$($matches[1]) கிராம்"; continue }
        if ($cw -match '^(\d+)\s*ml$') { $out += "$($matches[1]) மில்லி"; continue }
        if ($cw -match '^(\d+)\s*kg$') { $out += "$($matches[1]) கிலோ"; continue }
        if ($cw -match '^(\d+)\s*ltr$') { $out += "$($matches[1]) லிட்டர்"; continue }
        if ($cw -match '^(\d+)\s*l$') { $out += "$($matches[1]) லிட்டர்"; continue }
        if ($cw -match '^(\d+)(rs|ra)$') { $out += "$($matches[1]) ரூபாய்"; continue }
        if ($cw -match '^(\d+)g$') { $out += "$($matches[1]) கிராம்"; continue }
        if ($cw -match '^(\d+)ml$') { $out += "$($matches[1]) மில்லி"; continue }
        if ($cw -match '^(\d+)kg$') { $out += "$($matches[1]) கிலோ"; continue }
        if ($wm.ContainsKey($cw)) { $out += $wm[$cw]; continue }
        $out += $cw
    }
    $result = $out -join ' '
    $result = $result -replace '\s+', ' '
    return $result.Trim()
}

# Test if RPC function works
Write-Host "`nTesting RPC function..." -ForegroundColor Yellow
$testBody = @{ products_json = @(@{ id = "ac719c64-9f86-4a5b-afe6-896e9e111466"; tamil_name = "test" }) } | ConvertTo-Json -Depth 5 -Compress
try {
    Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/rpc/update_tamil_names" -Method Post -Headers $headers -Body $testBody -TimeoutSec 10 | Out-Null
    Write-Host "RPC function works!" -ForegroundColor Green
    $useRpc = $true
} catch {
    $errMsg = $_.Exception.Message
    if ($errMsg -match "record") {
        Write-Host "RPC function has wrong parameter type. Please run create_function.sql in Supabase SQL Editor first!" -ForegroundColor Red
        Write-Host "File: C:\Users\abuthahir\Documents\ideal_store\wholesale_market\create_function.sql" -ForegroundColor Yellow
    } else {
        Write-Host "RPC error: $errMsg" -ForegroundColor Red
    }
    $useRpc = $false
}

if (-not $useRpc) {
    Write-Host "`nFalling back to individual PATCH updates (requires RLS policy for anon)..." -ForegroundColor Yellow
}

# Process
$batchSize = if ($useRpc) { 50 } else { 1 }
$totalBatches = [math]::Ceiling($productsToUpdate.Count / $batchSize)
$successCount = 0
$failCount = 0
$startTime = Get-Date
Write-Host "`nProcessing $($productsToUpdate.Count) products in $totalBatches batches..." -ForegroundColor Green
Write-Host ("=" * 60)

for ($i = 0; $i -lt $productsToUpdate.Count; $i += $batchSize) {
    $batchNum = [math]::Floor($i / $batchSize) + 1
    $endIdx = [math]::Min($i + $batchSize, $productsToUpdate.Count)
    $batch = $productsToUpdate[$i..($endIdx - 1)]

    if ($useRpc) {
        $productsJson = @()
        foreach ($p in $batch) {
            $tamilName = Get-TamilName -name $p.name
            $productsJson += @{ id = $p.id; tamil_name = $tamilName }
        }
        $body = @{ products_json = $productsJson } | ConvertTo-Json -Depth 5 -Compress
        try {
            Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/rpc/update_tamil_names" -Method Post -Headers $headers -Body $body -TimeoutSec 30 | Out-Null
            $successCount += $batch.Count
        } catch {
            $failCount += $batch.Count
            if ($failCount -le 5) {
                $errMsg = $_.Exception.Message
                if ($errMsg.Length -gt 100) { $errMsg = $errMsg.Substring(0, 100) + "..." }
                Write-Host "[Batch $batchNum] FAIL - $errMsg" -ForegroundColor Red
            }
        }
    } else {
        foreach ($p in $batch) {
            $tamilName = Get-TamilName -name $p.name
            $body = @{ tamil_name = $tamilName } | ConvertTo-Json -Compress
            $filter = "id=eq.$($p.id)"
            try {
                Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?$filter" -Method Patch -Headers $headers -Body $body -TimeoutSec 10 | Out-Null
                $successCount++
            } catch {
                $failCount++
                if ($failCount -le 5) {
                    $errMsg = $_.Exception.Message
                    if ($errMsg.Length -gt 100) { $errMsg = $errMsg.Substring(0, 100) + "..." }
                    Write-Host "FAIL [$($p.name)]: $errMsg" -ForegroundColor Red
                }
            }
        }
    }

    if ($batchNum % 4 -eq 0 -or $batchNum -eq $totalBatches) {
        $elapsed = ((Get-Date) - $startTime).TotalSeconds
        $rate = if ($elapsed -gt 0) { [math]::Round($successCount / $elapsed, 1) } else { 0 }
        Write-Host "[Batch $batchNum/$totalBatches] Progress: $successCount OK, $failCount FAIL ($rate/sec)" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })
    }
}

$elapsed = ((Get-Date) - $startTime).TotalSeconds
Write-Host ("=" * 60)
Write-Host "`nCOMPLETE!" -ForegroundColor Cyan
Write-Host "Updated: $successCount | Failed: $failCount | Time: $([math]::Round($elapsed, 1))s" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })