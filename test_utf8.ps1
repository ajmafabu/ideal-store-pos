[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"
$SUPABASE_URL = "https://hrlciruepdstrvtsuoyr.supabase.co"
$API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhybGNpcnVlcGRzdHJ2dHN1b3lyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxMDA4MjgsImV4cCI6MjA5ODY3NjgyOH0.-FqYflyY-0333oNlC5clOpcOm_E60R6e9WULp_xZHEo"
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

function Invoke-PatchUtf8 {
    param([string]$Url, [hashtable]$Headers, [string]$JsonBody)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonBody)
    $webClient = New-Object System.Net.WebClient
    foreach ($h in $Headers.GetEnumerator()) {
        $webClient.Headers.Add($h.Key, $h.Value)
    }
    try {
        $responseBytes = $webClient.UploadData($Url, "PATCH", $bytes)
        return $true
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        throw $_
    } finally {
        $webClient.Dispose()
    }
}

# Test: does the failing product work with UTF-8 bytes?
Write-Host "=== UTF-8 BYTE TEST ===" -ForegroundColor Yellow
$testName = "bingo mad angles 5rs"
$testTamil = Get-TamilName -name $testName
$testBody = @{ tamil_name = $testTamil } | ConvertTo-Json -Compress
$testBytes = [System.Text.Encoding]::UTF8.GetBytes($testBody)
Write-Host "Name: $testName"
Write-Host "Tamil: $testTamil"
Write-Host "JSON string: $testBody"
Write-Host "JSON bytes ($($testBytes.Length)): $([BitConverter]::ToString($testBytes).Replace('-',' '))"

# Method 1: Use WebClient with UTF-8 bytes
$url = "$SUPABASE_URL/rest/v1/products?id=eq.ac719c64-9f86-4a5b-afe6-896e9e111466"
try {
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("apikey", $API_KEY)
    $wc.Headers.Add("Authorization", "Bearer $API_KEY")
    $wc.Headers.Add("Content-Type", "application/json; charset=utf-8")
    $wc.UploadData($url, "PATCH", $testBytes) | Out-Null
    Write-Host "WebClient: OK" -ForegroundColor Green
} catch {
    Write-Host "WebClient: FAIL - $($_.Exception.Message)" -ForegroundColor Red
} finally { $wc.Dispose() }

# Method 2: Use Invoke-WebRequest with -UseBasicParsing and explicit byte body
try {
    $resp = Invoke-WebRequest -Uri $url -Method Patch -Headers @{
        "apikey" = $API_KEY
        "Authorization" = "Bearer $API_KEY"
        "Content-Type" = "application/json; charset=utf-8"
        "Prefer" = "return=minimal"
    } -Body $testBytes -UseBasicParsing -TimeoutSec 15
    Write-Host "Invoke-WebRequest bytes: OK (Status $($resp.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "Invoke-WebRequest bytes: FAIL - $($_.Exception.Message)" -ForegroundColor Red
}
