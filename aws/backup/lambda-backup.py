import json
import boto3
import os
from datetime import datetime, timedelta
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
cloudwatch_client = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Lambda function to backup MapReduce data to S3
    """
    try:
        # Get environment variables
        source_bucket = os.environ.get('SOURCE_BUCKET')
        backup_bucket = os.environ.get('BACKUP_BUCKET')
        retention_days = int(os.environ.get('RETENTION_DAYS', '30'))
        
        logger.info(f"Starting backup from {source_bucket} to {backup_bucket}")
        
        # Get current timestamp
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        
        # List objects in source bucket
        source_objects = list_source_objects(source_bucket)
        
        if not source_objects:
            logger.info("No objects found in source bucket")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'No objects to backup',
                    'timestamp': timestamp
                })
            }
        
        # Backup objects
        backup_count = 0
        total_size = 0
        
        for obj in source_objects:
            try:
                # Create backup key with timestamp
                backup_key = f"backup/{timestamp}/{obj['Key']}"
                
                # Copy object to backup bucket
                copy_source = {
                    'Bucket': source_bucket,
                    'Key': obj['Key']
                }
                
                s3_client.copy_object(
                    CopySource=copy_source,
                    Bucket=backup_bucket,
                    Key=backup_key,
                    Metadata={
                        'original-bucket': source_bucket,
                        'original-key': obj['Key'],
                        'backup-timestamp': timestamp,
                        'original-size': str(obj['Size']),
                        'original-last-modified': obj['LastModified'].isoformat()
                    }
                )
                
                backup_count += 1
                total_size += obj['Size']
                
                logger.info(f"Backed up {obj['Key']} to {backup_key}")
                
            except Exception as e:
                logger.error(f"Error backing up {obj['Key']}: {str(e)}")
                continue
        
        # Clean up old backups
        cleanup_old_backups(backup_bucket, retention_days)
        
        # Send metrics to CloudWatch
        send_metrics(backup_count, total_size)
        
        logger.info(f"Backup completed: {backup_count} objects, {total_size} bytes")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Backup completed successfully',
                'timestamp': timestamp,
                'objects_backed_up': backup_count,
                'total_size_bytes': total_size
            })
        }
        
    except Exception as e:
        logger.error(f"Error in backup process: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Backup failed',
                'error': str(e)
            })
        }

def list_source_objects(bucket_name):
    """
    List all objects in the source bucket
    """
    objects = []
    paginator = s3_client.get_paginator('list_objects_v2')
    
    try:
        for page in paginator.paginate(Bucket=bucket_name):
            if 'Contents' in page:
                objects.extend(page['Contents'])
    except Exception as e:
        logger.error(f"Error listing objects in {bucket_name}: {str(e)}")
        raise
    
    return objects

def cleanup_old_backups(bucket_name, retention_days):
    """
    Clean up old backup files based on retention policy
    """
    try:
        cutoff_date = datetime.utcnow() - timedelta(days=retention_days)
        
        # List objects in backup bucket
        paginator = s3_client.get_paginator('list_objects_v2')
        
        for page in paginator.paginate(Bucket=bucket_name, Prefix='backup/'):
            if 'Contents' in page:
                for obj in page['Contents']:
                    # Check if object is older than retention period
                    if obj['LastModified'].replace(tzinfo=None) < cutoff_date:
                        try:
                            s3_client.delete_object(Bucket=bucket_name, Key=obj['Key'])
                            logger.info(f"Deleted old backup: {obj['Key']}")
                        except Exception as e:
                            logger.error(f"Error deleting {obj['Key']}: {str(e)}")
                            
    except Exception as e:
        logger.error(f"Error cleaning up old backups: {str(e)}")

def send_metrics(backup_count, total_size):
    """
    Send custom metrics to CloudWatch
    """
    try:
        cloudwatch_client.put_metric_data(
            Namespace='MapReduce/Backup',
            MetricData=[
                {
                    'MetricName': 'BackupObjectsCount',
                    'Value': backup_count,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'BackupSizeBytes',
                    'Value': total_size,
                    'Unit': 'Bytes',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'BackupSuccess',
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
    except Exception as e:
        logger.error(f"Error sending metrics: {str(e)}")

def restore_from_backup(source_bucket, backup_bucket, backup_key):
    """
    Restore a file from backup to source bucket
    """
    try:
        # Get backup object metadata
        response = s3_client.head_object(Bucket=backup_bucket, Key=backup_key)
        original_key = response['Metadata']['original-key']
        
        # Copy from backup to source
        copy_source = {
            'Bucket': backup_bucket,
            'Key': backup_key
        }
        
        s3_client.copy_object(
            CopySource=copy_source,
            Bucket=source_bucket,
            Key=original_key
        )
        
        logger.info(f"Restored {backup_key} to {original_key}")
        return True
        
    except Exception as e:
        logger.error(f"Error restoring {backup_key}: {str(e)}")
        return False

def list_backups(bucket_name, prefix='backup/'):
    """
    List all backup files in the backup bucket
    """
    backups = []
    
    try:
        paginator = s3_client.get_paginator('list_objects_v2')
        
        for page in paginator.paginate(Bucket=bucket_name, Prefix=prefix):
            if 'Contents' in page:
                for obj in page['Contents']:
                    backups.append({
                        'key': obj['Key'],
                        'size': obj['Size'],
                        'last_modified': obj['LastModified'],
                        'storage_class': obj.get('StorageClass', 'STANDARD')
                    })
    except Exception as e:
        logger.error(f"Error listing backups: {str(e)}")
        raise
    
    return backups

def get_backup_info(bucket_name, backup_key):
    """
    Get information about a specific backup
    """
    try:
        response = s3_client.head_object(Bucket=bucket_name, Key=backup_key)
        
        return {
            'key': backup_key,
            'size': response['ContentLength'],
            'last_modified': response['LastModified'],
            'metadata': response.get('Metadata', {}),
            'storage_class': response.get('StorageClass', 'STANDARD')
        }
    except Exception as e:
        logger.error(f"Error getting backup info for {backup_key}: {str(e)}")
        return None