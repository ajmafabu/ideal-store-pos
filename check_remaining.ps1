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

Write-Host "Fetching all products and checking Tamil names..." -ForegroundColor Cyan
$allProducts = @()
$page = 0
while ($true) {
    $offset = $page * 1000
    $resp = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?select=id,name,tamil_name&limit=1000&offset=$offset" -Method Get -Headers @{ "apikey" = $API_KEY; "Authorization" = "Bearer $API_KEY" } -TimeoutSec 15
    $allProducts += $resp
    if ($resp.Count -lt 1000) { break }
    $page++
}
$needUpdate = $allProducts | Where-Object { -not $_.tamil_name -or $_.tamil_name -eq "" }
Write-Host "Total: $($allProducts.Count) | Need update: $($needUpdate.Count)" -ForegroundColor Yellow

if ($needUpdate.Count -eq 0) {
    Write-Host "ALL DONE!" -ForegroundColor Green
    return
}

# Debug: check what's wrong with the first failing product
Write-Host "`n--- Debug: testing first product ---" -ForegroundColor Yellow
$testP = $needUpdate[0]
$tamilTest = Get-TamilName -name $testP.name
Write-Host "Name: '$($testP.name)' -> Tamil: '$tamilTest' (len=$($tamilTest.Length))"
$bodyObj = @{ tamil_name = $tamilTest }
$bodyJson = $bodyObj | ConvertTo-Json -Compress
Write-Host "JSON bytes: $([System.Text.Encoding]::UTF8.GetByteCount($bodyJson))"
$filter = "id=eq.$($testP.id)"
try {
    Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?$filter" -Method Patch -Headers $headers -Body $bodyJson -TimeoutSec 15 | Out-Null
    Write-Host "OK" -ForegroundColor Green
} catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    # Try to get response body
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("apikey", $API_KEY)
        $webClient.Headers.Add("Authorization", "Bearer $API_KEY")
        $webClient.Headers.Add("Content-Type", "application/json")
        $result = $webClient.UploadString("$SUPABASE_URL/rest/v1/products?$filter", "PATCH", $bodyJson)
        Write-Host "WebClient OK: $result" -ForegroundColor Green
    } catch {
        Write-Host "WebClient FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}
