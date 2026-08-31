[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"
$SUPABASE_URL = "https://hrlciruepdstrvtsuoyr.supabase.co"
$API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhybGNpcnVlcGRzdHJ2dHN1b3lyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxMDA4MjgsImV4cCI6MjA5ODY3NjgyOH0.-FqYflyY-0333oNlC5clOpcOm_E60R6e9WULp_xZHEo"
$dictPath = "C:\Users\abuthahir\Documents\ideal_store\wholesale_market\tamil_dict.json"
$dict = Get-Content $dictPath -Raw -Encoding UTF8 | ConvertFrom-Json
$wm = @{}
foreach ($prop in $dict.PSObject.Properties) { $wm[$prop.Name] = $prop.Value }

# Add unit translations to dictionary so we don't need hardcoded Tamil in the .ps1
$wm["rs"] = $wm["ரூபாய்"] # fallback
$wm["ra"] = $wm["ரூபாய்"]
$wm["r"] = $wm["ரூபாய்"]
$wm["g"] = $wm["கிராம்"]
$wm["gm"] = $wm["கிராம்"]
$wm["ml"] = $wm["மில்லி"]
$wm["kg"] = $wm["கிலோ"]
$wm["ltr"] = $wm["லிட்டர்"]
$wm["l"] = $wm["லிட்டர்"]

# Better: load unit translations from the json dict directly
# These are stored separately to avoid encoding issues with .ps1 files
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
            $tamilVal = $wm[$key]
            $n = $n.Replace($key, "|||$tamilVal|||")
        }
    }
    $words = $n -split '\s+'
    $out = @()
    foreach ($w in $words) {
        $cw = $w.Trim()
        if ($cw -eq "") { continue }
        if ($cw -match '^\|\|\|(.+)\|\|\|$') { $out += $matches[1]; continue }
        if ($cw -match '^\d+$') { $out += $cw; continue }
        if ($cw -match '^(\d+)\s*(rs|ra|r)$') {
            $num = $matches[1]
            $unit = $unitMap[$matches[2].ToLower()]
            $out += "$num $unit"; continue
        }
        if ($cw -match '^(\d+)\s*(g|gm|ml|kg|ltr|l)$') {
            $num = $matches[1]
            $unit = $unitMap[$matches[2].ToLower()]
            $out += "$num $unit"; continue
        }
        if ($cw -match '^(\d+)(rs|ra)$') {
            $num = $matches[1]
            $unit = $unitMap[$matches[2].ToLower()]
            $out += "$num $unit"; continue
        }
        if ($cw -match '^(\d+)(g|ml|kg)$') {
            $num = $matches[1]
            $unit = $unitMap[$matches[2].ToLower()]
            $out += "$num $unit"; continue
        }
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

# Test with the previously failing product using WebClient
Write-Host "`n--- Encoding test ---" -ForegroundColor Yellow
$testP = $needUpdate | Where-Object { $_.name -eq "bingo mad angles 5rs" } | Select-Object -First 1
if ($testP) {
    $tamilTest = Get-TamilName -name $testP.name
    $bodyTest = @{ tamil_name = $tamilTest } | ConvertTo-Json -Compress
    $bytesTest = [System.Text.Encoding]::UTF8.GetBytes($bodyTest)
    Write-Host "Name: $($testP.name)"
    Write-Host "Tamil: $tamilTest"
    Write-Host "UTF8 bytes: $([BitConverter]::ToString($bytesTest).Replace('-',' ').Substring(0,80))..."
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("apikey", $API_KEY)
    $wc.Headers.Add("Authorization", "Bearer $API_KEY")
    $wc.Headers.Add("Content-Type", "application/json; charset=utf-8")
    try {
        $wc.UploadData("$SUPABASE_URL/rest/v1/products?id=eq.$($testP.id)", "PATCH", $bytesTest) | Out-Null
        Write-Host "WebClient PATCH: OK" -ForegroundColor Green
    } catch {
        Write-Host "WebClient PATCH: FAIL - $($_.Exception.Message)" -ForegroundColor Red
    }
    $wc.Dispose()
}

$total = $needUpdate.Count
$successCount = 0
$failCount = 0
$startTime = Get-Date

Write-Host "`nUpdating $total products with UTF-8 WebClient..." -ForegroundColor Green
Write-Host ("=" * 60)

$wc = New-Object System.Net.WebClient
$wc.Headers.Add("apikey", $API_KEY)
$wc.Headers.Add("Authorization", "Bearer $API_KEY")
$wc.Headers.Add("Content-Type", "application/json; charset=utf-8")
$wc.Encoding = [System.Text.Encoding]::UTF8

for ($i = 0; $i -lt $needUpdate.Count; $i++) {
    $p = $needUpdate[$i]
    $tamilName = Get-TamilName -name $p.name
    $bodyJson = @{ tamil_name = $tamilName } | ConvertTo-Json -Compress
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)
    $url = "$SUPABASE_URL/rest/v1/products?id=eq.$($p.id)"

    $retries = 0
    $done = $false
    while (-not $done -and $retries -lt 3) {
        try {
            $wc.UploadData($url, "PATCH", $bodyBytes) | Out-Null
            $successCount++
            $done = $true
        } catch {
            $retries++
            if ($retries -lt 3) {
                Start-Sleep -Milliseconds 2000
            } else {
                $failCount++
                if ($failCount -le 10) {
                    $errMsg = $_.Exception.Message
                    if ($errMsg.Length -gt 80) { $errMsg = $errMsg.Substring(0, 80) }
                    Write-Host "  FAIL [$($p.name)]: $errMsg" -ForegroundColor Red
                }
            }
        }
    }

    if (($i + 1) % 25 -eq 0 -or ($i + 1) -eq $total) {
        $elapsed = ((Get-Date) - $startTime).TotalSeconds
        $rate = if ($elapsed -gt 0) { [math]::Round(($i + 1) / $elapsed, 1) } else { 0 }
        $pct = [math]::Round(($i + 1) / $total * 100)
        $remaining = $total - $i - 1
        $eta = if ($rate -gt 0) { [math]::Round($remaining / $rate) } else { 0 }
        $color = if ($failCount -eq 0) { "Green" } elseif ($failCount -lt 20) { "Yellow" } else { "Red" }
        Write-Host "[$($i+1)/$total] $pct%  OK:$successCount  FAIL:$failCount  ($rate/sec  ETA:${eta}s)" -ForegroundColor $color
    }

    Start-Sleep -Milliseconds 350
}
$wc.Dispose()

$elapsed = ((Get-Date) - $startTime).TotalSeconds
Write-Host ("=" * 60)
Write-Host "`nCOMPLETE!" -ForegroundColor Cyan
Write-Host "Updated: $successCount | Failed: $failCount | Time: $([math]::Round($elapsed, 1))s" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })

# Final verify
Write-Host "`nVerifying..." -ForegroundColor Yellow
$allCheck = @()
$page = 0
while ($true) {
    $offset = $page * 1000
    $resp = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?select=id,tamil_name&limit=1000&offset=$offset" -Method Get -Headers @{ "apikey" = $API_KEY; "Authorization" = "Bearer $API_KEY" } -TimeoutSec 15
    $allCheck += $resp
    if ($resp.Count -lt 1000) { break }
    $page++
}
$withTamil = ($allCheck | Where-Object { $_.tamil_name -and $_.tamil_name -ne "" }).Count
$withoutTamil = ($allCheck | Where-Object { -not $_.tamil_name -or $_.tamil_name -eq "" }).Count
Write-Host "Total: $($allCheck.Count) | With Tamil: $withTamil | Without Tamil: $withoutTamil" -ForegroundColor Cyan
Write-Host "`nSample Tamil names:" -ForegroundColor Yellow
$allCheck | Where-Object { $_.tamil_name -and $_.tamil_name -ne "" } | Select-Object -First 5 | ForEach-Object {
    Write-Host "  $($_.tamil_name)"
}
