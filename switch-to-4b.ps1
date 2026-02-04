# Switch from Qwen3-VL-8B to Qwen3-VL-4B
# Stops 8B first to free VRAM, then starts 4B

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Switching from 8B to 4B Model" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Stop 8B container
Write-Host "[1/4] Stopping 8B container..." -ForegroundColor Yellow
$eightBContainer = "vllm-qwen3vl-8b-latest"
if (docker ps --filter "name=$eightBContainer" --format "{{.Names}}" | Select-String $eightBContainer) {
    docker stop $eightBContainer
    Write-Host "✓ 8B container stopped" -ForegroundColor Green
} else {
    Write-Host "⚠ 8B container not running, skipping stop" -ForegroundColor Yellow
}
Write-Host ""

# Step 2: Update nginx config to point to 4B
Write-Host "[2/4] Updating nginx config to route to 4B..." -ForegroundColor Yellow
$nginxConfig = "nginx\api-proxy.conf"
$content = Get-Content $nginxConfig -Raw
$content = $content -replace "vllm-qwen3vl-8b-latest", "vllm-qwen3vl-4b-latest"
$content = $content -replace "Qwen3-VL-8B-Instruct", "Qwen3-VL-4B-Instruct"
Set-Content -Path $nginxConfig -Value $content -NoNewline
Write-Host "✓ Nginx config updated" -ForegroundColor Green
Write-Host ""

# Step 3: Start 4B container
Write-Host "[3/4] Starting 4B container..." -ForegroundColor Yellow
docker-compose --profile serve-latest up -d vllm-qwen3vl-4b-latest
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ 4B container started" -ForegroundColor Green
} else {
    Write-Host "✗ Failed to start 4B container" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 4: Wait for 4B to be healthy
Write-Host "[4/4] Waiting for 4B container to become healthy..." -ForegroundColor Yellow
Write-Host "This may take 1-2 minutes (model loading)..." -ForegroundColor Gray
$maxWait = 180  # 3 minutes max
$waitInterval = 5  # Check every 5 seconds
$elapsed = 0
$healthy = $false

while ($elapsed -lt $maxWait -and -not $healthy) {
    Start-Sleep -Seconds $waitInterval
    $elapsed += $waitInterval
    
    $status = docker ps --filter "name=vllm-qwen3vl-4b-latest" --format "{{.Status}}"
    if ($status -match "healthy") {
        $healthy = $true
        Write-Host "✓ 4B container is healthy!" -ForegroundColor Green
    } elseif ($status -match "unhealthy") {
        Write-Host "✗ 4B container is unhealthy!" -ForegroundColor Red
        Write-Host "Check logs: docker logs vllm-qwen3vl-4b-latest" -ForegroundColor Yellow
        exit 1
    } else {
        $percent = [math]::Min(100, ($elapsed / $maxWait * 100))
        Write-Host ('  Waiting... (' + $elapsed + '/' + $maxWait + ' seconds) - Status: ' + $status) -ForegroundColor Gray
    }
}

if (-not $healthy) {
    Write-Host "✗ Timeout waiting for 4B to become healthy" -ForegroundColor Red
    Write-Host "Check logs: docker logs vllm-qwen3vl-4b-latest" -ForegroundColor Yellow
    exit 1
}
Write-Host ""

# Step 5: Restart nginx to pick up new backend
Write-Host "[5/5] Restarting nginx proxy..." -ForegroundColor Yellow
docker restart vllm-api-proxy
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Nginx proxy restarted" -ForegroundColor Green
} else {
    Write-Host "⚠ Failed to restart nginx (may still work with DNS cache)" -ForegroundColor Yellow
}
Write-Host ""

# Step 6: Verify the switch
Write-Host "[6/6] Verifying switch..." -ForegroundColor Yellow
Start-Sleep -Seconds 3  # Give nginx a moment to start

try {
    $response = Invoke-WebRequest -Uri 'http://localhost:8081/v1/models' -UseBasicParsing -TimeoutSec 10
    $models = $response.Content | ConvertFrom-Json
    $modelName = $models.data[0].id
    
    if ($modelName -eq "Qwen/Qwen3-VL-4B-Instruct") {
        Write-Host "✓ Successfully switched to 4B model!" -ForegroundColor Green
        Write-Host "  Model: $modelName" -ForegroundColor Cyan
    } else {
        Write-Host "⚠ Unexpected model: $modelName" -ForegroundColor Yellow
    }
} catch {
    Write-Host '⚠ Could not verify model (nginx may still be starting)' -ForegroundColor Yellow
    Write-Host '  Try: curl http://localhost:8081/v1/models' -ForegroundColor Gray
}
Write-Host ""

# Summary
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Switch Complete!" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Current status:" -ForegroundColor Yellow
docker ps --filter "name=vllm" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
Write-Host ""
Write-Host "Access points:" -ForegroundColor Yellow
Write-Host '  - API: http://localhost:8081/v1' -ForegroundColor Cyan
Write-Host '  - Open-WebUI: http://localhost:3001' -ForegroundColor Cyan
Write-Host ""
Write-Host 'To switch back to 8B, run: .\switch-to-8b.ps1' -ForegroundColor Gray
