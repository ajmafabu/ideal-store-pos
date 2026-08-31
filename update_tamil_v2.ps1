$ErrorActionPreference = "Continue"
$SUPABASE_URL = "https://hrlciruepdstrvtsuoyr.supabase.co"
$API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhybGNpcnVlcGRzdHJ2dHN1b3lyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxMDA4MjgsImV4cCI6MjA5ODY3NjgyOH0.-FqYflyY-0333oNlC5clOpcOm_E60R6e9WULp_xZHEo"
$headers = @{ "apikey" = $API_KEY; "Authorization" = "Bearer $API_KEY"; "Content-Type" = "application/json" }
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

# Test RPC with a single item first
Write-Host "Testing RPC with single item..." -ForegroundColor Yellow
$testBody = @{ products_json = @(@{ id = $allProducts[0].id; tamil_name = (Get-TamilName -name $allProducts[0].name) }) } | ConvertTo-Json -Depth 5 -Compress
try {
    $resp = Invoke-WebRequest -Uri "$SUPABASE_URL/rest/v1/rpc/update_tamil_names" -Method Post -Headers $headers -Body $testBody -TimeoutSec 15
    Write-Host "Single item RPC: Status $($resp.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "Single item RPC error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Response: $($_.Exception.Response)" -ForegroundColor Red
}

# Test RPC with 2 items
Write-Host "`nTesting RPC with 2 items..." -ForegroundColor Yellow
$test2 = @()
for ($i = 0; $i -lt 2; $i++) {
    $test2 += @{ id = $allProducts[$i].id; tamil_name = (Get-TamilName -name $allProducts[$i].name) }
}
$body2 = @{ products_json = $test2 } | ConvertTo-Json -Depth 5 -Compress
try {
    $resp = Invoke-WebRequest -Uri "$SUPABASE_URL/rest/v1/rpc/update_tamil_names" -Method Post -Headers $headers -Body $body2 -TimeoutSec 15
    Write-Host "2 items RPC: Status $($resp.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "2 items RPC error: $($_.Exception.Message)" -ForegroundColor Red
}

# Now do all products in batches of 10 with detailed error reporting
$productsToUpdate = $allProducts | Where-Object { -not $_.tamil_name -or $_.tamil_name -eq "" }
Write-Host "`nTotal to update: $($productsToUpdate.Count)" -ForegroundColor Cyan

$batchSize = 10
$totalBatches = [math]::Ceiling($productsToUpdate.Count / $batchSize)
$successCount = 0
$failCount = 0
$startTime = Get-Date

Write-Host "Processing in batches of $batchSize ($totalBatches batches)..." -ForegroundColor Green

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

    try {
        $resp = Invoke-WebRequest -Uri "$SUPABASE_URL/rest/v1/rpc/update_tamil_names" -Method Post -Headers $headers -Body $body -TimeoutSec 30
        $successCount += $batch.Count
        if ($batchNum % 10 -eq 0 -or $batchNum -eq $totalBatches) {
            $elapsed = ((Get-Date) - $startTime).TotalSeconds
            $rate = if ($elapsed -gt 0) { [math]::Round($successCount / $elapsed, 1) } else { 0 }
            Write-Host "[Batch $batchNum/$totalBatches] OK: $successCount  FAIL: $failCount  ($rate/sec)" -ForegroundColor Green
        }
    } catch {
        $failCount += $batch.Count
        $errMsg = $_.Exception.Message
        if ($errMsg.Length -gt 200) { $errMsg = $errMsg.Substring(0, 200) + "..." }
        Write-Host "[Batch $batchNum] FAIL ($($batch.Count) items): $errMsg" -ForegroundColor Red
    }
}

$elapsed = ((Get-Date) - $startTime).TotalSeconds
Write-Host ("=" * 60)
Write-Host "DONE - Updated: $successCount | Failed: $failCount | Time: $([math]::Round($elapsed, 1))s" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })
