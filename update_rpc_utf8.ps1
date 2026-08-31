[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"
$SUPABASE_URL = "https://hrlciruepdstrvtsuoyr.supabase.co"
$API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhybGNpcnVlcGRzdHJ2dHN1b3lyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxMDA4MjgsImV4cCI6MjA5ODY3NjgyOH0.-FqYflyY-0333oNlC5clOpcOm_E60R6e9WULp_xZHEo"
$dictPath = "C:\Users\abuthahir\Documents\ideal_store\wholesale_market\tamil_dict.json"
$dict = Get-Content $dictPath -Raw -Encoding UTF8 | ConvertFrom-Json
$wm = @{}
foreach ($prop in $dict.PSObject.Properties) { $wm[$prop.Name] = $prop.Value }

$unitMap = @{
    "rs" = "ரூபாய்"; "ra" = "ரூபாய்"; "r" = "ரூபாய்"
    "g" = "கிராம்"; "gm" = "கிராம்"
    "ml" = "மில்லி"
    "kg" = "கிலோ"
    "ltr" = "லிட்டர்"; "l" = "லிட்டர்"
}

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
        if ($cw -match '^(\d+)\s*(rs|ra|r)$') { $out += "$($matches[1]) $($unitMap[$matches[2].ToLower()])"; continue }
        if ($cw -match '^(\d+)\s*(g|gm|ml|kg|ltr|l)$') { $out += "$($matches[1]) $($unitMap[$matches[2].ToLower()])"; continue }
        if ($cw -match '^(\d+)(rs|ra)$') { $out += "$($matches[1]) $($unitMap[$matches[2].ToLower()])"; continue }
        if ($cw -match '^(\d+)(g|ml|kg)$') { $out += "$($matches[1]) $($unitMap[$matches[2].ToLower()])"; continue }
        if ($wm.ContainsKey($cw)) { $out += $wm[$cw]; continue }
        $out += $cw
    }
    $result = $out -join ' '
    $result = $result -replace '\s+', ' '
    return $result.Trim()
}

Write-Host "Fetching products needing Tamil names..." -ForegroundColor Cyan
$needUpdate = @()
$page = 0
while ($true) {
    $offset = $page * 1000
    $resp = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?select=id,name,tamil_name&limit=1000&offset=$offset" -Method Get -Headers @{ "apikey" = $API_KEY; "Authorization" = "Bearer $API_KEY" } -TimeoutSec 15
    foreach ($p in $resp) { if (-not $p.tamil_name -or $p.tamil_name -eq "") { $needUpdate += $p } }
    if ($resp.Count -lt 1000) { break }
    $page++
}
Write-Host "Products to update: $($needUpdate.Count)" -ForegroundColor Yellow

if ($needUpdate.Count -eq 0) { Write-Host "ALL DONE!" -ForegroundColor Green; return }

$total = $needUpdate.Count
$successCount = 0
$failCount = 0
$startTime = Get-Date

$batchSize = 8
$totalBatches = [math]::Ceiling($total / $batchSize)

Write-Host "Updating via RPC in batches of $batchSize ($totalBatches batches)..." -ForegroundColor Green
Write-Host ("=" * 60)

$wc = New-Object System.Net.WebClient
$wc.Headers.Add("apikey", $API_KEY)
$wc.Headers.Add("Authorization", "Bearer $API_KEY")
$wc.Headers.Add("Content-Type", "application/json; charset=utf-8")

for ($i = 0; $i -lt $needUpdate.Count; $i += $batchSize) {
    $batchNum = [math]::Floor($i / $batchSize) + 1
    $endIdx = [math]::Min($i + $batchSize, $needUpdate.Count)
    $batch = $needUpdate[$i..($endIdx - 1)]

    $productsJson = @()
    foreach ($p in $batch) {
        $tamilName = Get-TamilName -name $p.name
        $productsJson += @{ id = $p.id; tamil_name = $tamilName }
    }
    $bodyObj = @{ products_json = $productsJson }
    $bodyJson = $bodyObj | ConvertTo-Json -Depth 5 -Compress
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)

    $retries = 0
    $done = $false
    while (-not $done -and $retries -lt 3) {
        try {
            $wc.UploadData("$SUPABASE_URL/rest/v1/rpc/update_tamil_names", "POST", $bodyBytes) | Out-Null
            $successCount += $batch.Count
            $done = $true
        } catch {
            $retries++
            if ($retries -lt 3) {
                Start-Sleep -Seconds 3
            } else {
                $failCount += $batch.Count
                $errMsg = $_.Exception.Message
                if ($errMsg.Length -gt 100) { $errMsg = $errMsg.Substring(0, 100) }
                if ($failCount -le 20) {
                    Write-Host "  [Batch $batchNum] FAIL: $errMsg" -ForegroundColor Red
                }
            }
        }
    }

    if ($batchNum % 5 -eq 0 -or $batchNum -eq $totalBatches) {
        $elapsed = ((Get-Date) - $startTime).TotalSeconds
        $rate = if ($elapsed -gt 0) { [math]::Round($successCount / $elapsed, 1) } else { 0 }
        $pct = [math]::Round($successCount / $total * 100)
        $eta = if ($rate -gt 0) { [math]::Round(($total - $successCount) / $rate) } else { 0 }
        $color = if ($failCount -eq 0) { "Green" } elseif ($failCount -lt 50) { "Yellow" } else { "Red" }
        Write-Host "[$batchNum/$totalBatches] $pct%  OK:$successCount  FAIL:$failCount  ($rate/sec  ETA:${eta}s)" -ForegroundColor $color
    }

    Start-Sleep -Milliseconds 800
}
$wc.Dispose()

$elapsed = ((Get-Date) - $startTime).TotalSeconds
Write-Host ("=" * 60)
Write-Host "`nCOMPLETE!" -ForegroundColor Cyan
Write-Host "Updated: $successCount | Failed: $failCount | Time: $([math]::Round($elapsed, 1))s" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })

# Final verify
Write-Host "`nFinal verification..." -ForegroundColor Yellow
$allProducts = @()
$page = 0
while ($true) {
    $offset = $page * 1000
    $resp = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?select=id,tamil_name&limit=1000&offset=$offset" -Method Get -Headers @{ "apikey" = $API_KEY; "Authorization" = "Bearer $API_KEY" } -TimeoutSec 15
    $allProducts += $resp
    if ($resp.Count -lt 1000) { break }
    $page++
}
$withTamil = ($allProducts | Where-Object { $_.tamil_name -and $_.tamil_name -ne "" }).Count
$withoutTamil = ($allProducts | Where-Object { -not $_.tamil_name -or $_.tamil_name -eq "" }).Count
Write-Host "Total: $($allProducts.Count) | With Tamil: $withTamil | Without Tamil: $withoutTamil" -ForegroundColor Cyan
Write-Host "`nSample Tamil names:" -ForegroundColor Yellow
$allProducts | Where-Object { $_.tamil_name -and $_.tamil_name -ne "" } | Select-Object -First 8 | ForEach-Object {
    Write-Host "  $($_.tamil_name)"
}
