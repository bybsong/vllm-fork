# Switch from Qwen3-VL-4B to Qwen3-VL-8B
# Stops 4B first to free VRAM, then starts 8B

Write-Host '============================================' -ForegroundColor Cyan
Write-Host 'Switching from 4B to 8B Model' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''

# Step 1: Stop 4B container
Write-Host '[1/4] Stopping 4B container...' -ForegroundColor Yellow
$fourBContainer = 'vllm-qwen3vl-4b-latest'
if (docker ps --filter "name=$fourBContainer" --format '{{.Names}}' | Select-String $fourBContainer) {
    docker stop $fourBContainer
    Write-Host '✓ 4B container stopped' -ForegroundColor Green
} else {
    Write-Host '⚠ 4B container not running, skipping stop' -ForegroundColor Yellow
}
Write-Host ''

# Step 2: Start 8B container
Write-Host '[2/4] Starting 8B container...' -ForegroundColor Yellow
docker-compose --profile serve-8b-latest up -d vllm-qwen3vl-8b-latest
if ($LASTEXITCODE -eq 0) {
    Write-Host '✓ 8B container started' -ForegroundColor Green
} else {
    Write-Host '✗ Failed to start 8B container' -ForegroundColor Red
    exit 1
}
Write-Host ''

# Step 3: Wait for 8B to be healthy
Write-Host '[3/4] Waiting for 8B container to become healthy...' -ForegroundColor Yellow
Write-Host 'This may take 2-3 minutes (model loading)...' -ForegroundColor Gray
$maxWait = 300
$waitInterval = 5
$elapsed = 0
$healthy = $false

while ($elapsed -lt $maxWait -and -not $healthy) {
    Start-Sleep -Seconds $waitInterval
    $elapsed += $waitInterval
    
    $status = docker ps --filter 'name=vllm-qwen3vl-8b-latest' --format '{{.Status}}'
    if ($status -match 'healthy') {
        $healthy = $true
        Write-Host '✓ 8B container is healthy!' -ForegroundColor Green
    } elseif ($status -match 'unhealthy') {
        Write-Host '✗ 8B container is unhealthy!' -ForegroundColor Red
        Write-Host 'Check logs: docker logs vllm-qwen3vl-8b-latest' -ForegroundColor Yellow
        exit 1
    } else {
        $waitMsg = '  Waiting... (' + $elapsed + '/' + $maxWait + ' seconds) - Status: ' + $status
        Write-Host $waitMsg -ForegroundColor Gray
    }
}

if (-not $healthy) {
    Write-Host '✗ Timeout waiting for 8B to become healthy' -ForegroundColor Red
    Write-Host 'Check logs: docker logs vllm-qwen3vl-8b-latest' -ForegroundColor Yellow
    exit 1
}
Write-Host ''

# Step 4: Restart nginx to pick up new backend
Write-Host '[4/4] Restarting nginx proxy...' -ForegroundColor Yellow
docker restart vllm-api-proxy
if ($LASTEXITCODE -eq 0) {
    Write-Host '✓ Nginx proxy restarted' -ForegroundColor Green
} else {
    Write-Host '⚠ Failed to restart nginx (may still work with DNS cache)' -ForegroundColor Yellow
}
Write-Host ''

# Step 5: Verify the switch
Write-Host '[5/5] Verifying switch...' -ForegroundColor Yellow
Start-Sleep -Seconds 3

try {
    $apiUrl = 'http://localhost:8081/v1/models'
    $response = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing -TimeoutSec 10
    $models = $response.Content | ConvertFrom-Json
    $modelName = $models.data[0].id
    
    if ($modelName -eq 'Qwen/Qwen3-VL-8B-Instruct') {
        Write-Host '✓ Successfully switched to 8B model!' -ForegroundColor Green
        Write-Host ('  Model: ' + $modelName) -ForegroundColor Cyan
    } else {
        Write-Host ('⚠ Unexpected model: ' + $modelName) -ForegroundColor Yellow
    }
} catch {
    Write-Host '⚠ Could not verify model (nginx may still be starting)' -ForegroundColor Yellow
    Write-Host '  Try: curl http://localhost:8081/v1/models' -ForegroundColor Gray
}
Write-Host ''

# Summary
Write-Host '============================================' -ForegroundColor Cyan
Write-Host 'Switch Complete!' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Current status:' -ForegroundColor Yellow
docker ps --filter 'name=vllm' --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
Write-Host ''
Write-Host 'Access points:' -ForegroundColor Yellow
Write-Host '  - API: http://localhost:8081/v1' -ForegroundColor Cyan
Write-Host '  - Open-WebUI: http://localhost:3001' -ForegroundColor Cyan
Write-Host ''
Write-Host 'To switch back to 4B, run: .\switch-to-4b.ps1' -ForegroundColor Gray
