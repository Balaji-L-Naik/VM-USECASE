import boto3

# Uses default region and credentials configured in your AWS CLI environment
s3_client = boto3.client('s3')
sfn_client = boto3.client('stepfunctions')

BUCKET_NAME = 'usecases-de'
PREFIX = 'data/pos_daily_drops/'
TARGET_NAME = 'vardhan-pos-ingestion-pipeline'

# 1. Dynamically locate the State Machine ARN by name
response = sfn_client.list_state_machines()
state_machine_arn = None

for sm in response.get('stateMachines', []):
    if TARGET_NAME in sm['name']:
        state_machine_arn = sm['stateMachineArn']
        break

if not state_machine_arn:
    print(f"ERROR: Could not find State Machine containing '{TARGET_NAME}'.")
    print("Available State Machines in your configured AWS region:")
    for sm in response.get('stateMachines', []):
        print(f" - {sm['name']}: {sm['stateMachineArn']}")
    exit(1)

print(f"Targeting State Machine: {state_machine_arn}\n")

# 2. Iterate S3 drops and launch Step Functions executions
paginator = s3_client.get_paginator('list_objects_v2')
pages = paginator.paginate(Bucket=BUCKET_NAME, Prefix=PREFIX)

triggered_count = 0

for page in pages:
    for obj in page.get('Contents', []):
        key = obj['Key']
        
        # Trigger only on CSV files, ignoring manifest files and directories
        if (key.endswith('.csv.gz') or key.endswith('.csv')) and not key.endswith('/'):
            print(f"Triggering execution for: {key}")
            sfn_client.start_execution(
                stateMachineArn=state_machine_arn,
                input=f'{{"file_key": "{key}"}}'
            )
            triggered_count += 1

print(f"\nCompleted: Triggered {triggered_count} executions across the dataset.")