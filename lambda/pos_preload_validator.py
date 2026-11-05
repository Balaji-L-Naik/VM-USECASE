import json
import hashlib
import boto3
import os
import gzip
import io
import csv

s3_client = boto3.client('s3')
sns_client = boto3.client('sns')

SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')
QUARANTINE_PREFIX = "data/quarantine_bad_data/"

SEEN_HASHES = set()

def lambda_handler(event, context):
    if 'detail' in event:
        bucket_name = event['detail']['bucket']['name']
        file_key = event['detail']['object']['key']
    elif 'bucket' in event and 'key' in event:
        bucket_name = event['bucket']
        file_key = event['key']
    else:
        raise ValueError("Invalid event input: Missing bucket or key.")
        
    if not file_key.startswith('data/pos_daily_drops/'):
        return {'status': 'SKIPPED', 'reason': 'Not in pos_daily_drops path'}
        
    if not (file_key.endswith('.csv.gz') or file_key.endswith('.csv')):
        return {'status': 'SKIPPED', 'reason': 'Non-CSV file'}

    # Safe Suffix Replacement for Manifest Key
    if file_key.endswith('.csv.gz'):
        manifest_key = file_key[:-7] + '.manifest.json'
    else:
        manifest_key = file_key[:-4] + '.manifest.json'

    filename = os.path.basename(file_key)

    try:
        csv_obj = s3_client.get_object(Bucket=bucket_name, Key=file_key)
        manifest_obj = s3_client.get_object(Bucket=bucket_name, Key=manifest_key)

        raw_bytes = csv_obj['Body'].read()
        manifest = json.loads(manifest_obj['Body'].read().decode('utf-8'))

        # Decompress Gzip if file is compressed
        if file_key.endswith('.csv.gz'):
            csv_text = gzip.decompress(raw_bytes).decode('utf-8', errors='ignore')
        else:
            csv_text = raw_bytes.decode('utf-8', errors='ignore')

        # Parse CSV safely using standard csv module
        reader = list(csv.reader(io.StringIO(csv_text.strip())))
        if not reader:
            raise ValueError("CSV file is empty.")

        data_rows = reader[1:]  # Exclude header row
        actual_rows = len(data_rows)
        expected_rows = int(manifest['lines'])
        expected_net = float(manifest['net_amount'])

        actual_net = 0.0
        for cols in data_rows:
            if len(cols) >= 10:
                try:
                    actual_net += float(cols[9].replace('"', '').strip())
                except ValueError:
                    pass

        actual_net = round(actual_net, 2)

        # Manifest Validation Check
        if actual_rows != expected_rows or abs(actual_net - expected_net) > 0.05:
            quarantine_key = f"{QUARANTINE_PREFIX}{filename}"

            s3_client.copy_object(
                Bucket=bucket_name,
                CopySource={'Bucket': bucket_name, 'Key': file_key},
                Key=quarantine_key
            )
            s3_client.delete_object(Bucket=bucket_name, Key=file_key)
            s3_client.delete_object(Bucket=bucket_name, Key=manifest_key)

            if SNS_TOPIC_ARN:
                sns_client.publish(
                    TopicArn=SNS_TOPIC_ARN,
                    Subject=f"ALERT: Manifest Mismatch - Quarantined {filename}",
                    Message=f"File {file_key} failed check.\nExpected Rows: {expected_rows} | Actual: {actual_rows}\nExpected Net: {expected_net} | Actual: {actual_net}"
                )

            return {'status': 'QUARANTINED', 'quarantine_key': quarantine_key}

        # SHA-256 Deduplication Check
        file_hash = hashlib.sha256(raw_bytes).hexdigest()
        if file_hash in SEEN_HASHES:
            return {'status': 'SILENT_SKIP', 'reason': 'Duplicate file hash'}

        SEEN_HASHES.add(file_hash)

        return {
            'status': 'PASSED',
            'bucket': bucket_name,
            'file_key': file_key,
            'manifest_key': manifest_key,
            'rows_verified': actual_rows,
            'net_amount_verified': actual_net
        }

    except Exception as e:
        if SNS_TOPIC_ARN:
            sns_client.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject=f"CRITICAL: Pre-Load Error on {filename}",
                Message=str(e)
            )
        raise e