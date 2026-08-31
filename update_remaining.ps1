[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"
$SUPABASE_URL = "https://hrlciruepdstrvtsuoyr.supabase.co"
$API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhybGNpcnVlcGRzdHJ2dHN1b3lyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxMDA4MjgsImV4cCI6MjA5ODY3NjgyOH0.-FqYflyY-0333oNlC5clOpcOm_E60R6e9WULp_xZHEo"
$headers = @{ "apikey" = $API_KEY; "Authorization" = "Bearer $API_KEY"; "Content-Type" = "application/json"; "Prefer" = "return=minimal" }
$dictPath = "C:\Users\abuthahir\Documents\ideal_store\wholesale_market\tamil_dict.json"
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

Write-Host "Fetching products needing Tamil names..." -ForegroundColor Cyan
$needUpdate = @()
$page = 0
while ($true) {
    $offset = $page * 1000
    $resp = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?select=id,name,tamil_name&limit=1000&offset=$offset" -Method Get -Headers @{ "apikey" = $API_KEY; "Authorization" = "Bearer $API_KEY" } -TimeoutSec 15
    foreach ($p in $resp) {
        if (-not $p.tamil_name -or $p.tamil_name -eq "") { $needUpdate += $p }
    }
    if ($resp.Count -lt 1000) { break }
    $page++
}
Write-Host "Products to update: $($needUpdate.Count)" -ForegroundColor Yellow

if ($needUpdate.Count -eq 0) {
    Write-Host "ALL DONE!" -ForegroundColor Green
    return
}

$total = $needUpdate.Count
$successCount = 0
$failCount = 0
$startTime = Get-Date

Write-Host "Updating one by one..." -ForegroundColor Green
Write-Host ("=" * 60)

for ($i = 0; $i -lt $needUpdate.Count; $i++) {
    $p = $needUpdate[$i]
    $tamilName = Get-TamilName -name $p.name
    $body = @{ tamil_name = $tamilName } | ConvertTo-Json -Compress
    $filter = "id=eq.$($p.id)"
    $url = "$SUPABASE_URL/rest/v1/products?$filter"

    $retries = 0
    $done = $false
    while (-not $done -and $retries -lt 3) {
        try {
            Invoke-RestMethod -Uri $url -Method Patch -Headers $headers -Body $body -TimeoutSec 15 | Out-Null
            $successCount++
            $done = $true
        } catch {
            $retries++
            if ($retries -lt 3) {
                Start-Sleep -Milliseconds 1500
            } else {
                $failCount++
                $errMsg = $_.Exception.Message
                if ($errMsg.Length -gt 80) { $errMsg = $errMsg.Substring(0, 80) }
                if ($failCount -le 5) {
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
        $color = if ($failCount -eq 0) { "Green" } elseif ($failCount -lt 50) { "Yellow" } else { "Red" }
        Write-Host "[$($i+1)/$total] $pct%  OK:$successCount  FAIL:$failCount  ($rate/sec  ETA:${eta}s)" -ForegroundColor $color
    }

    Start-Sleep -Milliseconds 400
}

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
