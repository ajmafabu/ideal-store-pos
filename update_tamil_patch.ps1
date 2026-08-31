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

# Check which products still need updating
Write-Host "Checking which products need Tamil names..." -ForegroundColor Cyan
$needUpdate = @()
$page = 0
$pageSize = 1000
while ($true) {
    $offset = $page * $pageSize
    $url = "$SUPABASE_URL/rest/v1/products?select=id,name,tamil_name&limit=$pageSize&offset=$offset"
    $resp = Invoke-RestMethod -Uri $url -Method Get -Headers @{ "apikey" = $API_KEY; "Authorization" = "Bearer $API_KEY" } -TimeoutSec 15
    if ($resp.Count -eq 0) { break }
    foreach ($p in $resp) {
        if (-not $p.tamil_name -or $p.tamil_name -eq "") {
            $needUpdate += $p
        }
    }
    if ($resp.Count -lt $pageSize) { break }
    $page++
}
Write-Host "Products needing Tamil name: $($needUpdate.Count)" -ForegroundColor Yellow

if ($needUpdate.Count -eq 0) {
    Write-Host "All products already have Tamil names!" -ForegroundColor Green
    return
}

$total = $needUpdate.Count
$successCount = 0
$failCount = 0
$startTime = Get-Date

Write-Host "Updating $total products one by one with 300ms delay..." -ForegroundColor Green
Write-Host ("=" * 60)

for ($i = 0; $i -lt $needUpdate.Count; $i++) {
    $p = $needUpdate[$i]
    $tamilName = Get-TamilName -name $p.name
    $body = @{ tamil_name = $tamilName } | ConvertTo-Json -Compress
    $filter = "id=eq.$($p.id)"

    $retries = 0
    $done = $false
    while (-not $done -and $retries -lt 3) {
        try {
            Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?$filter" -Method Patch -Headers $headers -Body $body -TimeoutSec 15 | Out-Null
            $successCount++
            $done = $true
        } catch {
            $retries++
            if ($retries -lt 3) {
                Start-Sleep -Seconds 2
            } else {
                $failCount++
                if ($failCount -le 10) {
                    Write-Host "  FAIL [$($p.name)]: $($_.Exception.Message.Substring(0, [Math]::Min(80, $_.Exception.Message.Length)))" -ForegroundColor Red
                }
            }
        }
    }

    if (($i + 1) % 50 -eq 0 -or ($i + 1) -eq $total) {
        $elapsed = ((Get-Date) - $startTime).TotalSeconds
        $rate = if ($elapsed -gt 0) { [math]::Round(($i + 1) / $elapsed, 1) } else { 0 }
        $pct = [math]::Round(($i + 1) / $total * 100)
        $eta = if ($rate -gt 0) { [math]::Round(($total - $i - 1) / $rate) } else { 0 }
        Write-Host "[$($i+1)/$total] $pct%  OK: $successCount  FAIL: $failCount  ($rate/sec  ETA: ${eta}s)" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })
    }

    Start-Sleep -Milliseconds 300
}

$elapsed = ((Get-Date) - $startTime).TotalSeconds
Write-Host ("=" * 60)
Write-Host "`nCOMPLETE!" -ForegroundColor Cyan
Write-Host "Updated: $successCount | Failed: $failCount | Time: $([math]::Round($elapsed, 1))s" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })

# Final verify
Write-Host "`nFinal verification..." -ForegroundColor Yellow
try {
    $countResp = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?select=id" -Method Get -Headers @{ "apikey" = $API_KEY; "Authorization" = "Bearer $API_KEY"; "Prefer" = "count=exact" } -TimeoutSec 15
    $totalCount = $countResp.Count
    $hasTamil = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?select=id&tamil_name=not.is.null&limit=1" -Method Get -Headers @{ "apikey" = $API_KEY; "Authorization" = "Bearer $API_KEY"; "Prefer" = "count=exact" } -TimeoutSec 15 -ErrorAction SilentlyContinue
    Write-Host "Total products: $totalCount" -ForegroundColor Cyan
    Write-Host "Products with Tamil name: $successCount (this run)" -ForegroundColor Green
} catch {
    Write-Host "Verify: $($_.Exception.Message)" -ForegroundColor Red
}
