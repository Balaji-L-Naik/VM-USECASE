import json
import hashlib
import boto3
import os
import gzip
import io
import csv
import urllib.parse
from botocore.exceptions import ClientError

s3_client = boto3.client('s3')
sns_client = boto3.client('sns')

SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')
QUARANTINE_PREFIX = "quarantine_bad_data/"

SEEN_HASHES = set()

def lambda_handler(event, context):
    filename = "unknown_file"
    try:
        # 1. Parse Bucket & Key from Step Functions payload or S3 Event
        if 'detail' in event:
            bucket_name = event['detail']['bucket']['name']
            file_key = event['detail']['object']['key']
        elif 'bucket' in event and 'key' in event:
            bucket_name = event['bucket']
            file_key = event['key']
        elif 'file_key' in event:
            bucket_name = event.get('bucket', 'usecases-de')
            file_key = event['file_key']
        else:
            raise ValueError("Invalid event payload: Missing bucket or file_key.")

        # Decode URL-encoded characters in key path (e.g. %20 or +)
        file_key = urllib.parse.unquote_plus(file_key)
        filename = os.path.basename(file_key)

        # 2. Path & File Type Guardrails
        if file_key.endswith('.manifest.json'):
            return {'status': 'SKIPPED', 'reason': 'Manifest file processed alongside CSV'}

        if not file_key.startswith('data/pos_daily_drops/'):
            return {'status': 'SKIPPED', 'reason': 'Not in pos_daily_drops path'}

        # Skip stock inventory files (they do not have manifest files)
        if '_stock_' in file_key:
            return {'status': 'SKIPPED', 'reason': 'Stock snapshot file (no manifest required)'}

        if not (file_key.endswith('.csv.gz') or file_key.endswith('.csv')):
            return {'status': 'SKIPPED', 'reason': 'Non-CSV file'}

        # 3. Derive Manifest S3 Key Name
        if file_key.endswith('.csv.gz'):
            manifest_key = file_key[:-7] + '.manifest.json'
        else:
            manifest_key = file_key[:-4] + '.manifest.json'

        # 4. Fetch CSV File from S3
        try:
            csv_obj = s3_client.get_object(Bucket=bucket_name, Key=file_key)
        except ClientError as e:
            if e.response['Error']['Code'] == 'NoSuchKey':
                return {'status': 'SKIPPED', 'reason': f'CSV file {file_key} no longer exists'}
            raise e

        # 5. Fetch Manifest File from S3
        try:
            manifest_obj = s3_client.get_object(Bucket=bucket_name, Key=manifest_key)
        except ClientError as e:
            if e.response['Error']['Code'] == 'NoSuchKey':
                if SNS_TOPIC_ARN:
                    sns_client.publish(
                        TopicArn=SNS_TOPIC_ARN,
                        Subject=f"ALERT: Missing Manifest File for {filename}",
                        Message=f"Sales file {file_key} arrived without expected manifest key: {manifest_key}"
                    )
                return {'status': 'FAILED_MISSING_MANIFEST', 'reason': f'Manifest {manifest_key} not found'}
            raise e

        # 6. Parse Manifest Fields Flexibly
        raw_bytes = csv_obj['Body'].read()
        manifest = json.loads(manifest_obj['Body'].read().decode('utf-8'))

        expected_rows_val = None
        for k in ['line_count', 'lines', 'rows', 'row_count', 'total_lines']:
            if k in manifest:
                expected_rows_val = manifest[k]
                break

        expected_net_val = None
        for k in ['net_amount', 'net_amt', 'total_net']:
            if k in manifest:
                expected_net_val = manifest[k]
                break

        if expected_rows_val is None or expected_net_val is None:
            raise KeyError(f"Manifest missing expected row/net keys. Found keys: {list(manifest.keys())}")

        expected_rows = int(expected_rows_val)
        expected_net = float(expected_net_val)

        # 7. Read and Decompress CSV Data
        if file_key.endswith('.csv.gz'):
            csv_text = gzip.decompress(raw_bytes).decode('utf-8', errors='ignore')
        else:
            csv_text = raw_bytes.decode('utf-8', errors='ignore')

        reader = list(csv.reader(io.StringIO(csv_text.strip())))
        if not reader:
            raise ValueError("CSV file is empty.")

        header = [c.strip().lower() for c in reader[0]]
        data_rows = reader[1:]  # Exclude CSV header row
        actual_rows = len(data_rows)

        # 8. Dynamic Net Amount Column Resolution
        net_col_idx = -1
        for col_alias in ['line_amount', 'net_amount', 'line_amt', 'net_amt', 'amount', 'total_amount']:
            if col_alias in header:
                net_col_idx = header.index(col_alias)
                break
        
        # Fallback to index 9 if no named header matches
        if net_col_idx == -1:
            net_col_idx = 9 if len(header) > 9 else len(header) - 1

        # Calculate actual net amount across data rows
        actual_net = 0.0
        for cols in data_rows:
            if len(cols) > net_col_idx:
                raw_val = cols[net_col_idx].replace('"', '').replace(',', '').strip()
                if raw_val.startswith('(') and raw_val.endswith(')'):
                    raw_val = '-' + raw_val[1:-1]
                try:
                    if raw_val:
                        actual_net += float(raw_val)
                except ValueError:
                    pass

        actual_net = round(actual_net, 2)

        # 9. Verify Line Count and Net Amount Against Manifest
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
                    Message=f"File {file_key} failed validation.\nExpected Rows: {expected_rows} | Actual: {actual_rows}\nExpected Net: {expected_net} | Actual: {actual_net}"
                )

            return {
                'status': 'QUARANTINED',
                'quarantine_key': quarantine_key,
                'expected_rows': expected_rows,
                'actual_rows': actual_rows,
                'expected_net': expected_net,
                'actual_net': actual_net
            }

        # 10. Deduplication Check (SHA-256 Hash)
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
                Message=f"Error Type: {type(e).__name__}\nDetails: {str(e)}"
            )
        raise e