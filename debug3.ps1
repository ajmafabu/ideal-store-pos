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

# Check encoding: test a simple ASCII-only name
Write-Host "=== ENCODING TEST ===" -ForegroundColor Yellow

# Use a product with simple name
$testP = $allProducts | Where-Object { $_.name -match '^[a-z0-9 ]+$' -and $_.name.Length -lt 20 } | Select-Object -First 1
$tamilTest = Get-TamilName -name $testP.name
Write-Host "Simple test: '$($testP.name)' -> '$tamilTest'"

# Test PATCH with ConvertTo-Json
$bodyObj = @{ tamil_name = $tamilTest }
$bodyJson = $bodyObj | ConvertTo-Json -Compress
Write-Host "JSON body: $bodyJson"
$filter = "id=eq.$($testP.id)"
try {
    Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?$filter" -Method Patch -Headers $headers -Body $bodyJson -TimeoutSec 15 | Out-Null
    Write-Host "PATCH simple: SUCCESS" -ForegroundColor Green
} catch {
    $errMsg = $_.Exception.Message
    Write-Host "PATCH simple: FAIL - $errMsg" -ForegroundColor Red
}

# Test RPC with ConvertTo-Json
Write-Host "`n=== RPC TEST ===" -ForegroundColor Yellow
$rpcBody = @{ products_json = @(@{ id = $testP.id; tamil_name = $tamilTest }) } | ConvertTo-Json -Depth 5 -Compress
Write-Host "RPC JSON length: $($rpcBody.Length)"
try {
    Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/rpc/update_tamil_names" -Method Post -Headers $headers -Body $rpcBody -TimeoutSec 15 | Out-Null
    Write-Host "RPC simple: SUCCESS" -ForegroundColor Green
} catch {
    Write-Host "RPC simple: FAIL - $($_.Exception.Message)" -ForegroundColor Red
}

# Now test with multi-word translated name (contains Tamil)
Write-Host "`n=== TAMIL NAME TEST ===" -ForegroundColor Yellow
$roseP = $allProducts | Where-Object { $_.name -match '3 rose' } | Select-Object -First 1
$tamilRose = Get-TamilName -name $roseP.name
Write-Host "Product: '$($roseP.name)' -> Tamil: '$tamilRose'"

$bodyRose = @{ tamil_name = $tamilRose } | ConvertTo-Json -Compress
$filterRose = "id=eq.$($roseP.id)"
try {
    Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?$filterRose" -Method Patch -Headers $headers -Body $bodyRose -TimeoutSec 15 | Out-Null
    Write-Host "PATCH tamil: SUCCESS" -ForegroundColor Green
} catch {
    Write-Host "PATCH tamil: FAIL - $($_.Exception.Message)" -ForegroundColor Red
}

# Check what the UTF-8 bytes look like for the Tamil string
Write-Host "`n=== UTF-8 CHECK ===" -ForegroundColor Yellow
$bytes = [System.Text.Encoding]::UTF8.GetBytes($tamilRose)
Write-Host "UTF-8 bytes ($($bytes.Length)): $($bytes -join ',')"
$hex = ($bytes | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
Write-Host "Hex: $hex"

# Check how many products have names containing quotes or special chars
$specialProducts = $allProducts | Where-Object { $_.name -match '["''\\]' }
Write-Host "`nProducts with quotes/backslashes: $($specialProducts.Count)"
if ($specialProducts.Count -gt 0) {
    $specialProducts | Select-Object -First 3 | ForEach-Object { Write-Host "  '$($_.name)'" }
}
