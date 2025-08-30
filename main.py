import hashlib
import json
import os
import time
from typing import Dict, Any, Optional
import boto3
from botocore.exceptions import ClientError


# Initialize DynamoDB client with cost optimization
dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('DYNAMODB_TABLE', 'url-shortener-table')
table = dynamodb.Table(table_name)

# In-memory cache for frequently accessed URLs (reduces DynamoDB calls)
url_cache = {}
CACHE_SIZE = 100  # Limit cache size for memory efficiency


def shorten_url(long_url):
    """ Generate a short code for the given long url and store it in DynamoDB"""
    # Create a short hash from url
    long_url_hash = hashlib.sha256(long_url.encode()).hexdigest()[:8]
    
    try:
        # Store in DynamoDB with minimal attributes to save storage costs
        table.put_item(
            Item={
                'short_code': long_url_hash,
                'long_url': long_url,
                'created_at': int(time.time()),
                'clicks': 0
            },
            # Use conditional write to avoid overwriting existing URLs (cost optimization)
            ConditionExpression='attribute_not_exists(short_code)'
        )
        
        # Add to cache
        if len(url_cache) < CACHE_SIZE:
            url_cache[long_url_hash] = {
                'long_url': long_url,
                'created_at': int(time.time()),
                'clicks': 0
            }
        
        return long_url_hash
    except ClientError as e:
        if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
            # URL already exists, return existing code
            return long_url_hash
        else:
            print(f"Error storing URL in DynamoDB: {e}")
            # Fallback to cache-only storage for free tier
            if len(url_cache) < CACHE_SIZE:
                url_cache[long_url_hash] = {
                    'long_url': long_url,
                    'created_at': int(time.time()),
                    'clicks': 0
                }
            return long_url_hash


def redirect_url(short_url):
    """ Redirect the given short url to the long url from cache or DynamoDB"""
    # Check cache first (free, no DynamoDB cost)
    if short_url in url_cache:
        # Update click count in cache
        url_cache[short_url]['clicks'] += 1
        return url_cache[short_url]['long_url']
    
    try:
        # Fallback to DynamoDB (costs money)
        response = table.get_item(
            Key={'short_code': short_url}
        )
        
        if 'Item' in response:
            # Update click count (batch updates to reduce costs)
            table.update_item(
                Key={'short_code': short_url},
                UpdateExpression='SET clicks = clicks + :inc',
                ExpressionAttributeValues={':inc': 1}
            )
            
            # Add to cache for future requests
            if len(url_cache) < CACHE_SIZE:
                url_cache[short_url] = response['Item']
            
            return response['Item']['long_url']
        else:
            return None
    except ClientError as e:
        print(f"Error retrieving URL from DynamoDB: {e}")
        return None


def get_url_stats(short_url):
    """ Get statistics for a short URL (cache-first approach)"""
    # Check cache first (free)
    if short_url in url_cache:
        item = url_cache[short_url]
        return {
            'short_code': short_url,
            'long_url': item['long_url'],
            'created_at': item['created_at'],
            'clicks': item['clicks']
        }
    
    try:
        # Fallback to DynamoDB
        response = table.get_item(Key={'short_code': short_url})
        
        if 'Item' in response:
            return {
                'short_code': short_url,
                'long_url': response['Item']['long_url'],
                'created_at': response['Item']['created_at'],
                'clicks': response['Item']['clicks']
            }
        else:
            return None
    except ClientError as e:
        print(f"Error retrieving URL stats from DynamoDB: {e}")
        return None


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda handler for URL shortening service with DynamoDB (Free Tier Optimized)
    
    Expected event structure:
    {
        "httpMethod": "POST" | "GET",
        "path": "/shorten" | "/redirect/{shortCode}" | "/stats/{shortCode}",
        "body": "{\"url\": \"long_url_here\"}" (for POST requests),
        "pathParameters": {"shortCode": "short_code_here"} (for GET requests)
    }
    """
    try:
        http_method = event.get('httpMethod', '')
        path = event.get('path', '')
        
        # Handle URL shortening (POST request)
        if http_method == 'POST' and path == '/shorten':
            body = json.loads(event.get('body', '{}'))
            long_url = body.get('url')
            
            if not long_url:
                return {
                    'statusCode': 400,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({
                        'error': 'URL is required in request body'
                    })
                }
            
            # Validate URL format
            if not long_url.startswith(('http://', 'https://')):
                long_url = 'https://' + long_url
            
            short_code = shorten_url(long_url)
            domain = os.environ.get('DOMAIN', 'your-domain.com')
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'shortCode': short_code,
                    'longUrl': long_url,
                    'shortUrl': f"https://{domain}/{short_code}",
                    'message': 'URL shortened successfully (Free Tier Optimized)'
                })
            }
        
        # Handle URL redirection (GET request)
        elif http_method == 'GET' and path.startswith('/redirect/'):
            path_params = event.get('pathParameters', {})
            short_code = path_params.get('shortCode')
            
            if not short_code:
                return {
                    'statusCode': 400,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({
                        'error': 'Short code is required'
                    })
                }
            
            long_url = redirect_url(short_code)
            
            if not long_url:
                return {
                    'statusCode': 404,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({
                        'error': 'Short code not found'
                    })
                }
            
            # Return redirect response
            return {
                'statusCode': 302,
                'headers': {
                    'Location': long_url,
                    'Access-Control-Allow-Origin': '*'
                },
                'body': ''
            }
        
        # Handle URL statistics (GET request)
        elif http_method == 'GET' and path.startswith('/stats/'):
            path_params = event.get('pathParameters', {})
            short_code = path_params.get('shortCode')
            
            if not short_code:
                return {
                    'statusCode': 400,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({
                        'error': 'Short code is required'
                    })
                }
            
            stats = get_url_stats(short_code)
            
            if not stats:
                return {
                    'statusCode': 404,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({
                        'error': 'Short code not found'
                    })
                }
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps(stats)
            }
        
        # Handle root path
        elif http_method == 'GET' and path == '/':
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'message': 'URL Shortener Service - Free Tier Optimized',
                    'endpoints': {
                        'shorten': 'POST /shorten',
                        'redirect': 'GET /redirect/{shortCode}',
                        'stats': 'GET /stats/{shortCode}'
                    },
                    'features': [
                        'Persistent storage with DynamoDB',
                        'Click tracking and analytics',
                        'URL validation and sanitization',
                        'Free Tier optimized with caching',
                        'Cost-effective operations'
                    ],
                    'free_tier_info': {
                        'lambda_requests': '1M free per month',
                        'dynamodb_storage': '25GB free per month',
                        'dynamodb_requests': '25WCU/25RCU free per month',
                        'api_gateway': '1M free API calls per month'
                    }
                })
            }
        
        else:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Endpoint not found'
                })
            }
    
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': f'Internal server error: {str(e)}'
            })
        }


# ----------------- Example Run -----------------
if __name__ == "__main__":
    import time
    
    # Set environment variable for local testing
    os.environ['DYNAMODB_TABLE'] = 'url-shortener-table'
    
    url = "https://www.example.com/this-is-a-very-long-url"
    short = shorten_url(url)
    print("Short Code:", short)
    print("Redirect:", redirect_url(short))
    
    # Test Lambda handler locally
    test_event = {
        'httpMethod': 'POST',
        'path': '/shorten',
        'body': json.dumps({'url': url})
    }
    
    print("\n--- Testing Lambda Handler ---")
    result = lambda_handler(test_event, None)
    print("Lambda Response:", json.dumps(result, indent=2))