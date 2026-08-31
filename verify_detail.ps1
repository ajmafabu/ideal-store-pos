[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$SUPABASE_URL = "https://hrlciruepdstrvtsuoyr.supabase.co"
$API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhybGNpcnVlcGRzdHJ2dHN1b3lyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxMDA4MjgsImV4cCI6MjA5ODY3NjgyOH0.-FqYflyY-0333oNlC5clOpcOm_E60R6e9WULp_xZHEo"
$headers = @{ "apikey" = $API_KEY; "Authorization" = "Bearer $API_KEY" }

# Check specific product we know was updated
Write-Host "--- Checking specific products ---" -ForegroundColor Yellow
$resp = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?id=eq.ac719c64-9f86-4a5b-afe6-896e9e111466&select=id,name,tamil_name" -Method Get -Headers $headers -TimeoutSec 15
Write-Host "Product '1 kg 3 rose':"
Write-Host "  name: $($resp[0].name)"
Write-Host "  tamil_name: '$($resp[0].tamil_name)'"
if ($resp[0].tamil_name) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($resp[0].tamil_name)
    Write-Host "  tamil_name bytes ($($bytes.Length)): $([BitConverter]::ToString($bytes).Replace('-',' '))"
}

# Count again more carefully
Write-Host "`n--- Counting Tamil names ---" -ForegroundColor Yellow
$allProducts = @()
$page = 0
while ($true) {
    $offset = $page * 1000
    $r = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?select=id,name,tamil_name&limit=1000&offset=$offset" -Method Get -Headers $headers -TimeoutSec 15
    $allProducts += $r
    if ($r.Count -lt 1000) { break }
    $page++
}
Write-Host "Total: $($allProducts.Count)"
$withTamil = $allProducts | Where-Object { $_.tamil_name -and $_.tamil_name -ne "" }
$withoutTamil = $allProducts | Where-Object { -not $_.tamil_name -or $_.tamil_name -eq "" }
Write-Host "With Tamil: $($withTamil.Count)"
Write-Host "Without Tamil: $($withoutTamil.Count)"

Write-Host "`nSample with Tamil (first 5):" -ForegroundColor Green
$withTamil | Select-Object -First 5 | ForEach-Object { Write-Host "  $($_.name) -> $($_.tamil_name)" }

Write-Host "`nSample without Tamil (first 5):" -ForegroundColor Red
$withoutTamil | Select-Object -First 5 | ForEach-Object { Write-Host "  $($_.name) (id=$($_.id))" }

# Test direct PATCH on one of the "without" products
if ($withoutTamil.Count -gt 0) {
    Write-Host "`n--- Direct PATCH test ---" -ForegroundColor Yellow
    $testP = $withoutTamil[0]
    Write-Host "Trying to update: $($testP.name) (id=$($testP.id))"
    $dictPath = "C:\Users\abuthahir\Documents\ideal_store\wholesale_market\tamil_dict.json"
    $dict = Get-Content $dictPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $wm = @{}
    foreach ($prop in $dict.PSObject.Properties) { $wm[$prop.Name] = $prop.Value }
    $n = $testP.name.ToLower().Trim() -replace "[^a-z0-9\s]" -replace "\s+", " "
    foreach ($key in ($wm.Keys | Sort-Object { $_.Length } -Descending)) {
        if ($key.Contains(" ") -and $n.Contains($key)) { $n = $n.Replace($key, "TAMILKEY") }
    }
    $simpleTamil = "test_tamil_update"
    $bodyJson = @{ tamil_name = $simpleTamil } | ConvertTo-Json -Compress
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("apikey", $API_KEY)
    $wc.Headers.Add("Authorization", "Bearer $API_KEY")
    $wc.Headers.Add("Content-Type", "application/json; charset=utf-8")
    try {
        $wc.UploadData("$SUPABASE_URL/rest/v1/products?id=eq.$($testP.id)", "PATCH", $bodyBytes) | Out-Null
        Write-Host "PATCH: OK" -ForegroundColor Green
        # Read back
        Start-Sleep -Seconds 1
        $check = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/products?id=eq.$($testP.id)&select=tamil_name" -Method Get -Headers $headers -TimeoutSec 15
        Write-Host "Read back tamil_name: '$($check[0].tamil_name)'" -ForegroundColor Green
    } catch {
        Write-Host "PATCH: FAIL - $($_.Exception.Message)" -ForegroundColor Red
    }
    $wc.Dispose()
}
