$ErrorActionPreference = "Stop"
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

# Debug: Check products data
Write-Host "=== PRODUCT DATA DEBUG ===" -ForegroundColor Yellow
Write-Host "Total products: $($allProducts.Count)"
Write-Host "First 3 products:"
for ($i = 0; $i -lt 3; $i++) {
    $p = $allProducts[$i]
    $tn = Get-TamilName -name $p.name
    Write-Host "  [$i] name='$($p.name)' id=$($p.id) tamil='$tn' tamil_name='$($p.tamil_name)'"
}

$productsToUpdate = $allProducts | Where-Object { -not $_.tamil_name -or $_.tamil_name -eq "" }
Write-Host "`nProducts needing update: $($productsToUpdate.Count)"

# Debug: Test RPC with explicit JSON construction
Write-Host "`n=== RPC DEBUG ===" -ForegroundColor Yellow
$testId = $productsToUpdate[0].id
$testTamil = Get-TamilName -name $productsToUpdate[0].name
Write-Host "Testing with id=$testId tamil=$testTamil"

# Try building JSON manually to avoid PowerShell serialization issues
$jsonBody = '{\"products_json\":[{\"id\":\"' + $testId + '\",\"tamil_name\":\"' + ($testTamil -replace '"', '\"') + '\"}]}'
Write-Host "Manual JSON: $jsonBody"

try {
    $resp = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/rpc/update_tamil_names" -Method Post -Headers $headers -Body $jsonBody -TimeoutSec 15
    Write-Host "RPC success! Response: $resp" -ForegroundColor Green
} catch {
    Write-Host "RPC error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $errBody = $sr.ReadToEnd()
        Write-Host "Error body: $errBody" -ForegroundColor Red
    }
}

# Try PATCH directly
Write-Host "`n=== PATCH DEBUG ===" -ForegroundColor Yellow
$patchBody = '{\"tamil_name\":\"' + ($testTamil -replace '"', '\"') + '\"}'
$patchFilter = "id=eq.$testId"
Write-Host "PATCH body: $patchBody"
try {
    $resp = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?$patchFilter" -Method Patch -Headers $headers -Body $patchBody -TimeoutSec 15
    Write-Host "PATCH success! Response: $($resp | ConvertTo-Json -Compress)" -ForegroundColor Green
} catch {
    Write-Host "PATCH error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $sr = New-Object System.IO.StreamReader($Exception.Response.GetResponseStream())
        $errBody = $sr.ReadToEnd()
        Write-Host "Error body: $errBody" -ForegroundColor Red
    }
}
