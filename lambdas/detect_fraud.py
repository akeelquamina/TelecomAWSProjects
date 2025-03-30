import json

def lambda_handler(event, context):
    suspicious_calls = []
    for record in event['records']:
        if record['call_type'] == 'international' and record['call_duration'] < 3:
            suspicious_calls.append(record)
    return {
        'statusCode': 200,
        'body': json.dumps({'suspicious_calls': suspicious_calls})
    }
