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
    foreach ($p in $resp) { if (-not $p.tamil_name -or $p.tamil_name -eq "") { $needUpdate += $p } }
    if ($resp.Count -lt 1000) { break }
    $page++
}
Write-Host "Products to update: $($needUpdate.Count)" -ForegroundColor Yellow

if ($needUpdate.Count -eq 0) { Write-Host "ALL DONE!" -ForegroundColor Green; return }

# Debug first 5 failures to find root cause
Write-Host "`n--- Debugging persistent failures ---" -ForegroundColor Yellow
$debugNames = @("bingo mad angles 5rs", "SUPER MILK 10RS", "AACHI SAMBAR 5Rs", "siip 10rs 15""")
foreach ($dn in $debugNames) {
    $match = $needUpdate | Where-Object { $_.name -eq $dn }
    if ($match) {
        $tn = Get-TamilName -name $match.name
        $body = @{ tamil_name = $tn } | ConvertTo-Json -Compress
        Write-Host "Name: '$($match.name)'"
        Write-Host "  Tamil: '$tn'"
        Write-Host "  JSON body: $body"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        Write-Host "  JSON UTF8 bytes: $($bytes.Length)"
        try {
            Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?id=eq.$($match.id)" -Method Patch -Headers $headers -Body $body -TimeoutSec 10 | Out-Null
            Write-Host "  Result: OK" -ForegroundColor Green
        } catch {
            $errMsg = $_.Exception.Message
            Write-Host "  Result: FAIL - $errMsg" -ForegroundColor Red
            # Try with 5 second wait and retry
            Start-Sleep -Seconds 5
            try {
                Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?id=eq.$($match.id)" -Method Patch -Headers $headers -Body $body -TimeoutSec 10 | Out-Null
                Write-Host "  Retry: OK (after 5s wait)" -ForegroundColor Green
            } catch {
                Write-Host "  Retry: FAIL - $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        Start-Sleep -Milliseconds 500
    }
}

# Now re-fetch and check remaining
Write-Host "`n--- Rechecking remaining ---" -ForegroundColor Yellow
$needUpdate2 = @()
$page = 0
while ($true) {
    $offset = $page * 1000
    $resp = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?select=id,name,tamil_name&limit=1000&offset=$offset" -Method Get -Headers @{ "apikey" = $API_KEY; "Authorization" = "Bearer $API_KEY" } -TimeoutSec 15
    foreach ($p in $resp) { if (-not $p.tamil_name -or $p.tamil_name -eq "") { $needUpdate2 += $p } }
    if ($resp.Count -lt 1000) { break }
    $page++
}
Write-Host "Still need update: $($needUpdate2.Count)" -ForegroundColor Cyan
$needUpdate2 | Select-Object -First 10 | ForEach-Object {
    Write-Host "  $($_.name)"
}
