# URL Shortener Lambda Deployment Script for Windows - Free Tier Optimized
# This script helps deploy the URL shortener service to AWS Lambda within Free Tier limits

param(
    [string]$StackName = "url-shortener-free-tier",
    [string]$Environment = "dev",
    [string]$DomainName = "your-domain.com",
    [string]$Region = "us-east-1"
)

Write-Host "🚀 Deploying URL Shortener Service to AWS Lambda (Free Tier Optimized)..." -ForegroundColor Green
Write-Host "Stack Name: $StackName" -ForegroundColor Yellow
Write-Host "Environment: $Environment (Recommended: dev for free tier)" -ForegroundColor Yellow
Write-Host "Domain: $DomainName" -ForegroundColor Yellow
Write-Host "Region: $Region" -ForegroundColor Yellow
Write-Host ""

# Free Tier Information
Write-Host "💰 AWS Free Tier Limits:" -ForegroundColor Cyan
Write-Host "  • Lambda: 1M requests/month" -ForegroundColor White
Write-Host "  • DynamoDB: 25GB storage + 25WCU/25RCU" -ForegroundColor White
Write-Host "  • API Gateway: 1M API calls/month" -ForegroundColor White
Write-Host "  • Data Transfer: 15GB/month" -ForegroundColor White
Write-Host ""

# Check if AWS CLI is installed
try {
    aws --version | Out-Null
    Write-Host "✅ AWS CLI is installed" -ForegroundColor Green
} catch {
    Write-Host "❌ AWS CLI is not installed. Please install it first." -ForegroundColor Red
    Write-Host "Download from: https://aws.amazon.com/cli/" -ForegroundColor Yellow
    exit 1
}

# Check if AWS credentials are configured
try {
    aws sts get-caller-identity | Out-Null
    Write-Host "✅ AWS credentials are configured" -ForegroundColor Green
} catch {
    Write-Host "❌ AWS credentials are not configured. Please run 'aws configure' first." -ForegroundColor Red
    exit 1
}

# Check if environment is set to dev for free tier
if ($Environment -eq "prod") {
    Write-Host "⚠️  Warning: Using 'prod' environment may exceed free tier limits!" -ForegroundColor Yellow
    Write-Host "   Consider using 'dev' environment for free tier testing." -ForegroundColor Yellow
    $continue = Read-Host "Continue with prod? (y/N)"
    if ($continue -ne "y" -and $continue -ne "Y") {
        Write-Host "Deployment cancelled. Use 'dev' environment for free tier." -ForegroundColor Yellow
        exit 0
    }
}

# Create deployment package
Write-Host "📦 Creating deployment package..." -ForegroundColor Blue
try {
    if (Test-Path "lambda-deployment.zip") {
        Remove-Item "lambda-deployment.zip" -Force
    }
    
    # Create a temporary directory for packaging
    $tempDir = "temp-lambda-package"
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    
    # Copy main.py to temp directory
    Copy-Item "main.py" -Destination $tempDir
    
    # Install dependencies
    Write-Host "📥 Installing Python dependencies..." -ForegroundColor Blue
    pip install -r requirements.txt -t $tempDir --quiet
    
    # Create deployment package
    Compress-Archive -Path "$tempDir\*" -DestinationPath "lambda-deployment.zip" -Force
    
    # Clean up temp directory
    Remove-Item $tempDir -Recurse -Force
    
    Write-Host "✅ Deployment package created: lambda-deployment.zip" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to create deployment package" -ForegroundColor Red
    exit 1
}

# Deploy using CloudFormation
Write-Host "☁️ Deploying CloudFormation stack..." -ForegroundColor Blue
try {
    aws cloudformation deploy `
        --template-file template.yaml `
        --stack-name $StackName `
        --parameter-overrides `
            Environment=$Environment `
            DomainName=$DomainName `
        --capabilities CAPABILITY_IAM `
        --region $Region
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ CloudFormation stack deployed successfully!" -ForegroundColor Green
    } else {
        Write-Host "❌ CloudFormation deployment failed" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ Failed to deploy CloudFormation stack" -ForegroundColor Red
    exit 1
}

# Get stack outputs
Write-Host "📋 Getting stack outputs..." -ForegroundColor Blue
try {
    $outputs = aws cloudformation describe-stacks `
        --stack-name $StackName `
        --region $Region `
        --query 'Stacks[0].Outputs' `
        --output json | ConvertFrom-Json
    
    Write-Host "✅ Stack deployed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "📊 Stack Outputs:" -ForegroundColor Cyan
    foreach ($output in $outputs) {
        Write-Host "  $($output.OutputKey): $($output.OutputValue)" -ForegroundColor White
    }
    
    # Extract API URL and Function URL
    $apiUrl = ($outputs | Where-Object { $_.OutputKey -eq "ApiUrl" }).OutputValue
    $functionUrl = ($outputs | Where-Object { $_.OutputKey -eq "LambdaFunctionUrl" }).OutputValue
    
    Write-Host ""
    Write-Host "🎯 Your URL Shortener Service is now live!" -ForegroundColor Green
    Write-Host "API Gateway URL: $apiUrl" -ForegroundColor Yellow
    Write-Host "Direct Lambda URL: $functionUrl" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "📝 Test the service:" -ForegroundColor Cyan
    Write-Host "  Shorten URL: POST $apiUrl/shorten" -ForegroundColor White
    Write-Host "  Redirect: GET $apiUrl/redirect/{shortCode}" -ForegroundColor White
    Write-Host "  Stats: GET $apiUrl/stats/{shortCode}" -ForegroundColor White
    Write-Host "  Info: GET $apiUrl" -ForegroundColor White
    Write-Host ""
    Write-Host "🔗 Direct Lambda testing:" -ForegroundColor Cyan
    Write-Host "  POST $functionUrl" -ForegroundColor White
    
} catch {
    Write-Host "❌ Failed to get stack outputs" -ForegroundColor Red
}

# Free Tier Cost Monitoring
Write-Host ""
Write-Host "💰 Free Tier Cost Monitoring:" -ForegroundColor Cyan
Write-Host "  • Monitor costs in AWS Cost Explorer" -ForegroundColor White
Write-Host "  • Set up billing alerts in AWS Billing Console" -ForegroundColor White
Write-Host "  • Free tier expires after 12 months" -ForegroundColor White
Write-Host "  • Current usage: aws ce get-cost-and-usage" -ForegroundColor White

Write-Host ""
Write-Host "🎉 Deployment completed!" -ForegroundColor Green
Write-Host "Your service is optimized for AWS Free Tier usage." -ForegroundColor Yellow
Write-Host "Check the AWS Console for more details." -ForegroundColor Yellow
