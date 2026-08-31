[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"
$SUPABASE_URL = "https://hrlciruepdstrvtsuoyr.supabase.co"
$API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhybGNpcnVlcGRzdHJ2dHN1b3lyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxMDA4MjgsImV4cCI6MjA5ODY3NjgyOH0.-FqYflyY-0333oNlC5clOpcOm_E60R6e9WULp_xZHEo"
$headers = @{ "apikey" = $API_KEY; "Authorization" = "Bearer $API_KEY"; "Content-Type" = "application/json"; "Prefer" = "return=minimal" }
$filePath = "C:\Users\abuthahir\Documents\ideal_store\wholesale_market\products_list.json"
$dictPath = "C:\Users\abuthahir\Documents\ideal_store\wholesale_market\tamil_dict.json"
$allProducts = Get-Content $filePath -Raw -Encoding UTF8 | ConvertFrom-Json
$dict = Get-Content $dictPath -Raw -Encoding UTF8 | ConvertFrom-Json

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

$productsToUpdate = $allProducts | Where-Object { -not $_.tamil_name -or $_.tamil_name -eq "" }
Write-Host "Total: $($allProducts.Count) | To update: $($productsToUpdate.Count)" -ForegroundColor Cyan

$batchSize = 10
$totalBatches = [math]::Ceiling($productsToUpdate.Count / $batchSize)
$successCount = 0
$failCount = 0
$retryCount = 0
$startTime = Get-Date

Write-Host "Processing in batches of $batchSize ($totalBatches batches) with 1s delay..." -ForegroundColor Green
Write-Host ("=" * 60)

for ($i = 0; $i -lt $productsToUpdate.Count; $i += $batchSize) {
    $batchNum = [math]::Floor($i / $batchSize) + 1
    $endIdx = [math]::Min($i + $batchSize, $productsToUpdate.Count)
    $batch = $productsToUpdate[$i..($endIdx - 1)]

    $productsJson = @()
    foreach ($p in $batch) {
        $tamilName = Get-TamilName -name $p.name
        $productsJson += @{ id = $p.id; tamil_name = $tamilName }
    }
    $body = @{ products_json = $productsJson } | ConvertTo-Json -Depth 5 -Compress

    $retried = $false
    while ($true) {
        try {
            Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/rpc/update_tamil_names" -Method Post -Headers $headers -Body $body -TimeoutSec 30 | Out-Null
            $successCount += $batch.Count
            break
        } catch {
            $errMsg = $_.Exception.Message
            if ($errMsg.Length -gt 150) { $errMsg = $errMsg.Substring(0, 150) + "..." }
            if (-not $retried) {
                $retryCount++
                $retried = $true
                Start-Sleep -Seconds 3
            } else {
                $failCount += $batch.Count
                if ($failCount -le 20) {
                    Write-Host "[Batch $batchNum] FAIL: $errMsg" -ForegroundColor Red
                }
                break
            }
        }
    }

    if ($batchNum % 5 -eq 0 -or $batchNum -eq $totalBatches) {
        $elapsed = ((Get-Date) - $startTime).TotalSeconds
        $rate = if ($elapsed -gt 0) { [math]::Round($successCount / $elapsed, 1) } else { 0 }
        $color = if ($failCount -eq 0) { "Green" } elseif ($failCount -lt 100) { "Yellow" } else { "Red" }
        Write-Host "[Batch $batchNum/$totalBatches] OK: $successCount  FAIL: $failCount  RETRY: $retryCount  ($rate/sec)" -ForegroundColor $color
    }

    Start-Sleep -Milliseconds 1200
}

$elapsed = ((Get-Date) - $startTime).TotalSeconds
Write-Host ("=" * 60)
Write-Host "`nCOMPLETE!" -ForegroundColor Cyan
Write-Host "Updated: $successCount | Failed: $failCount | Retries: $retryCount | Time: $([math]::Round($elapsed, 1))s" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })

# Verify
Write-Host "`nVerifying..." -ForegroundColor Yellow
try {
    $check = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?select=id,tamil_name&tamil_name=not.is.null&limit=5" -Method Get -Headers $headers -TimeoutSec 15
    Write-Host "Sample updated products:" -ForegroundColor Green
    $check | ForEach-Object { Write-Host "  tamil_name: $($_.tamil_name)" }
    $countAll = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?select=id&tamil_name=not.is.null" -Method Get -Headers @{ "apikey" = $API_KEY; "Authorization" = "Bearer $API_KEY"; "Prefer" = "count=exact" } -TimeoutSec 15
    Write-Host "Total products with Tamil names: $($countAll.Count)" -ForegroundColor Cyan
} catch {
    Write-Host "Verify error: $($_.Exception.Message)" -ForegroundColor Red
}
