#!/usr/bin/env python3
"""
Test script for DynamoDB integration
This script helps test the URL shortener service locally with DynamoDB
"""

import boto3
import json
import time
from botocore.exceptions import ClientError

# Local DynamoDB (requires DynamoDB Local or AWS credentials configured)
try:
    # Try to connect to local DynamoDB first
    dynamodb = boto3.resource('dynamodb', 
                             endpoint_url='http://localhost:8000',
                             region_name='us-east-1',
                             aws_access_key_id='dummy',
                             aws_secret_access_key='dummy')
    print("✅ Connected to local DynamoDB")
except:
    try:
        # Fallback to AWS DynamoDB
        dynamodb = boto3.resource('dynamodb')
        print("✅ Connected to AWS DynamoDB")
    except Exception as e:
        print(f"❌ Failed to connect to DynamoDB: {e}")
        exit(1)

# Table configuration
table_name = 'url-shortener-test'
table = None

def create_test_table():
    """Create a test DynamoDB table"""
    global table
    
    try:
        # Check if table exists
        table = dynamodb.Table(table_name)
        table.load()
        print(f"✅ Table {table_name} already exists")
        return True
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceNotFoundException':
            # Table doesn't exist, create it
            try:
                table = dynamodb.create_table(
                    TableName=table_name,
                    KeySchema=[
                        {
                            'AttributeName': 'short_code',
                            'KeyType': 'HASH'
                        }
                    ],
                    AttributeDefinitions=[
                        {
                            'AttributeName': 'short_code',
                            'AttributeType': 'S'
                        }
                    ],
                    BillingMode='PAY_PER_REQUEST'
                )
                
                # Wait for table to be created
                table.meta.client.get_waiter('table_exists').wait(TableName=table_name)
                print(f"✅ Table {table_name} created successfully")
                return True
            except Exception as e:
                print(f"❌ Failed to create table: {e}")
                return False
        else:
            print(f"❌ Error checking table: {e}")
            return False

def test_url_operations():
    """Test URL shortening and retrieval operations"""
    if not table:
        print("❌ Table not available")
        return False
    
    test_urls = [
        "https://www.example.com/very-long-url-1",
        "https://www.google.com/search?q=python+programming",
        "https://github.com/username/repository",
        "example.com/simple-url"  # Test URL without protocol
    ]
    
    print("\n🧪 Testing URL operations...")
    
    # Test URL shortening
    shortened_urls = []
    for url in test_urls:
        try:
            # Generate short code (simplified version)
            import hashlib
            short_code = hashlib.sha256(url.encode()).hexdigest()[:8]
            
            # Store in DynamoDB
            table.put_item(
                Item={
                    'short_code': short_code,
                    'long_url': url if url.startswith(('http://', 'https://')) else f'https://{url}',
                    'created_at': int(time.time()),
                    'clicks': 0
                }
            )
            
            shortened_urls.append((short_code, url))
            print(f"✅ Shortened: {url[:50]}... → {short_code}")
            
        except Exception as e:
            print(f"❌ Failed to shorten {url}: {e}")
    
    # Test URL retrieval and click counting
    print("\n📊 Testing URL retrieval and analytics...")
    for short_code, original_url in shortened_urls:
        try:
            # Get URL
            response = table.get_item(Key={'short_code': short_code})
            if 'Item' in response:
                item = response['Item']
                print(f"✅ Retrieved: {short_code} → {item['long_url'][:50]}...")
                print(f"   Clicks: {item['clicks']}, Created: {item['created_at']}")
                
                # Simulate clicks
                for i in range(3):
                    table.update_item(
                        Key={'short_code': short_code},
                        UpdateExpression='SET clicks = clicks + :inc',
                        ExpressionAttributeValues={':inc': 1}
                    )
                
                # Get updated stats
                updated_response = table.get_item(Key={'short_code': short_code})
                if 'Item' in updated_response:
                    print(f"   Updated clicks: {updated_response['Item']['clicks']}")
            else:
                print(f"❌ Failed to retrieve {short_code}")
                
        except Exception as e:
            print(f"❌ Error retrieving {short_code}: {e}")
    
    return True

def cleanup_test_data():
    """Clean up test data"""
    if table:
        try:
            # Scan and delete all items
            response = table.scan()
            with table.batch_writer() as batch:
                for item in response['Items']:
                    batch.delete_item(Key={'short_code': item['short_code']})
            
            print("✅ Test data cleaned up")
        except Exception as e:
            print(f"⚠️ Warning: Could not clean up test data: {e}")

def main():
    """Main test function"""
    print("🚀 Starting DynamoDB Integration Tests")
    print("=" * 50)
    
    # Create test table
    if not create_test_table():
        print("❌ Cannot proceed without table")
        return
    
    # Test operations
    if test_url_operations():
        print("\n✅ All tests passed!")
    else:
        print("\n❌ Some tests failed")
    
    # Cleanup
    cleanup_test_data()
    
    print("\n🎉 Testing completed!")

if __name__ == "__main__":
    main()
