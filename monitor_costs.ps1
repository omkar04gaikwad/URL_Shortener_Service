# AWS Free Tier Cost Monitoring Script
# This script helps monitor your AWS usage to stay within Free Tier limits

param(
    [string]$Region = "us-east-1"
)

Write-Host "💰 AWS Free Tier Cost Monitoring" -ForegroundColor Green
Write-Host "=================================" -ForegroundColor Green
Write-Host ""

# Check if AWS CLI is installed
try {
    aws --version | Out-Null
} catch {
    Write-Host "❌ AWS CLI is not installed. Please install it first." -ForegroundColor Red
    exit 1
}

# Check if AWS credentials are configured
try {
    aws sts get-caller-identity | Out-Null
} catch {
    Write-Host "❌ AWS credentials are not configured. Please run 'aws configure' first." -ForegroundColor Red
    exit 1
}

# Get current month costs
Write-Host "📊 Current Month Costs:" -ForegroundColor Cyan
try {
    $currentMonth = Get-Date -Format "yyyy-MM-01"
    $nextMonth = (Get-Date).AddMonths(1).ToString("yyyy-MM-01")
    
    $costs = aws ce get-cost-and-usage `
        --time-period Start=$currentMonth,End=$nextMonth `
        --granularity MONTHLY `
        --metrics BlendedCost `
        --group-by Type=DIMENSION,Key=SERVICE `
        --region $Region `
        --output json | ConvertFrom-Json
    
    if ($costs.ResultsByTime.Count -gt 0) {
        $totalCost = $costs.ResultsByTime[0].Total.BlendedCost.Amount
        $totalCostFormatted = [math]::Round([double]$totalCost, 4)
        
        if ([double]$totalCost -eq 0) {
            Write-Host "✅ Current month cost: $0.00 (Within Free Tier)" -ForegroundColor Green
        } elseif ([double]$totalCost -lt 1) {
            Write-Host "⚠️  Current month cost: $$totalCostFormatted (Low cost)" -ForegroundColor Yellow
        } else {
            Write-Host "🚨 Current month cost: $$totalCostFormatted (May exceed Free Tier)" -ForegroundColor Red
        }
        
        Write-Host ""
        Write-Host "📋 Service Breakdown:" -ForegroundColor Cyan
        foreach ($group in $costs.ResultsByTime[0].Groups) {
            $serviceName = $group.Keys[0]
            $serviceCost = [math]::Round([double]$group.Metrics.BlendedCost.Amount, 4)
            if ([double]$serviceCost -gt 0) {
                Write-Host "  $serviceName`: $$serviceCost" -ForegroundColor White
            }
        }
    } else {
        Write-Host "ℹ️  No cost data available for current month" -ForegroundColor Blue
    }
} catch {
    Write-Host "⚠️  Could not retrieve cost data. You may not have Cost Explorer access." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "📈 Free Tier Usage Monitoring:" -ForegroundColor Cyan

# Lambda usage
Write-Host "🔧 Lambda Usage:" -ForegroundColor Blue
try {
    $lambdaMetrics = aws cloudwatch get-metric-statistics `
        --namespace AWS/Lambda `
        --metric-name Invocations `
        --start-time (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ss") `
        --end-time (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss") `
        --period 2592000 `
        --statistics Sum `
        --region $Region `
        --output json | ConvertFrom-Json
    
    if ($lambdaMetrics.Datapoints.Count -gt 0) {
        $invocations = $lambdaMetrics.Datapoints[0].Sum
        $freeLimit = 1000000
        $percentage = [math]::Round(($invocations / $freeLimit) * 100, 2)
        
        if ($invocations -lt $freeLimit) {
            Write-Host "  ✅ Invocations: $invocations / $freeLimit ($percentage%)" -ForegroundColor Green
        } else {
            Write-Host "  🚨 Invocations: $invocations / $freeLimit ($percentage%) - EXCEEDED!" -ForegroundColor Red
        }
    } else {
        Write-Host "  ℹ️  No Lambda invocation data available" -ForegroundColor Blue
    }
} catch {
    Write-Host "  ⚠️  Could not retrieve Lambda metrics" -ForegroundColor Yellow
}

# DynamoDB usage
Write-Host "🗄️  DynamoDB Usage:" -ForegroundColor Blue
try {
    $dynamoMetrics = aws cloudwatch get-metric-statistics `
        --namespace AWS/DynamoDB `
        --metric-name ConsumedReadCapacityUnits `
        --start-time (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ss") `
        --end-time (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss") `
        --period 2592000 `
        --statistics Sum `
        --region $Region `
        --output json | ConvertFrom-Json
    
    if ($dynamoMetrics.Datapoints.Count -gt 0) {
        $readUnits = $dynamoMetrics.Datapoints[0].Sum
        $freeLimit = 25000000  # 25 RCU * 30 days * 24 hours * 3600 seconds
        $percentage = [math]::Round(($readUnits / $freeLimit) * 100, 2)
        
        if ($readUnits -lt $freeLimit) {
            Write-Host "  ✅ Read Units: $readUnits / $freeLimit ($percentage%)" -ForegroundColor Green
        } else {
            Write-Host "  🚨 Read Units: $readUnits / $freeLimit ($percentage%) - EXCEEDED!" -ForegroundColor Red
        }
    } else {
        Write-Host "  ℹ️  No DynamoDB read data available" -ForegroundColor Blue
    }
} catch {
    Write-Host "  ⚠️  Could not retrieve DynamoDB metrics" -ForegroundColor Yellow
}

# API Gateway usage
Write-Host "🌐 API Gateway Usage:" -ForegroundColor Blue
try {
    $apiMetrics = aws cloudwatch get-metric-statistics `
        --namespace AWS/ApiGateway `
        --metric-name Count `
        --start-time (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ss") `
        --end-time (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss") `
        --period 2592000 `
        --statistics Sum `
        --region $Region `
        --output json | ConvertFrom-Json
    
    if ($apiMetrics.Datapoints.Count -gt 0) {
        $apiCalls = $apiMetrics.Datapoints[0].Sum
        $freeLimit = 1000000
        $percentage = [math]::Round(($apiCalls / $freeLimit) * 100, 2)
        
        if ($apiCalls -lt $freeLimit) {
            Write-Host "  ✅ API Calls: $apiCalls / $freeLimit ($percentage%)" -ForegroundColor Green
        } else {
            Write-Host "  🚨 API Calls: $apiCalls / $freeLimit ($percentage%) - EXCEEDED!" -ForegroundColor Red
        }
    } else {
        Write-Host "  ℹ️  No API Gateway data available" -ForegroundColor Blue
    }
} catch {
    Write-Host "  ⚠️  Could not retrieve API Gateway metrics" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "💡 Cost Control Tips:" -ForegroundColor Cyan
Write-Host "  • Set up billing alerts in AWS Billing Console" -ForegroundColor White
Write-Host "  • Monitor usage daily during development" -ForegroundColor White
Write-Host "  • Use 'dev' environment for testing" -ForegroundColor White
Write-Host "  • Clean up unused resources regularly" -ForegroundColor White
Write-Host "  • Free Tier expires after 12 months" -ForegroundColor White

Write-Host ""
Write-Host "🔗 Useful Commands:" -ForegroundColor Cyan
Write-Host "  • Check costs: aws ce get-cost-and-usage --time-period Start=2024-01-01,End=2024-01-31" -ForegroundColor White
Write-Host "  • Set billing alert: aws cloudwatch put-metric-alarm" -ForegroundColor White
Write-Host "  • Monitor Lambda: aws cloudwatch get-metric-statistics --namespace AWS/Lambda" -ForegroundColor White

Write-Host ""
Write-Host "🎯 Next Steps:" -ForegroundColor Green
Write-Host "  1. Set up billing alerts in AWS Console" -ForegroundColor White
Write-Host "  2. Monitor usage weekly" -ForegroundColor White
Write-Host "  3. Optimize code if approaching limits" -ForegroundColor White
Write-Host "  4. Consider paid plans when needed" -ForegroundColor White

Write-Host ""
Write-Host "✅ Cost monitoring completed!" -ForegroundColor Green
