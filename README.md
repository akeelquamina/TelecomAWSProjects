# Telecom Fraud Detection with AWS

## Overview
This project focuses on building a Telecom Fraud Detection System using AWS services. The system detects anomalies in call patterns and stores relevant data in DynamoDB for analysis. The development was divided into two phases:

- **Phase 1:** Setting up the Lambda function to store call data in DynamoDB.
- **Phase 2:** Enhancing the system with anomaly detection and expanding data attributes.

## Phase 1: Setting Up AWS Lambda with DynamoDB

### 1. Create an AWS Lambda Function
1. Navigate to AWS Lambda and create a new function.
2. Choose **Node.js 18.x** as the runtime.
3. Set up IAM permissions to allow Lambda to write to DynamoDB.

### 2. Install Dependencies
Ensure your development environment has the necessary dependencies:
```sh
npm init -y
npm install @aws-sdk/client-dynamodb uuid
```

### 3. Write the Lambda Function
Create an `index.js` file with the following content:

```javascript
import { DynamoDBClient, PutItemCommand } from "@aws-sdk/client-dynamodb";
import { v4 as uuidv4 } from "uuid";

const dynamoDB = new DynamoDBClient({ region: "us-east-2" });

export const handler = async (event) => {
    try {
        const callID = uuidv4();
        const params = {
            TableName: process.env.TABLE_NAME || "TelecomCalls",
            Item: {
                callID: { S: callID },
                phoneNumber: { S: event.phoneNumber },
                callDuration: { N: event.callDuration.toString() },
                riskScore: { N: event.riskScore.toString() },
                timestamp: { S: new Date().toISOString() }, // Required as sort key
                callType: { S: event.callType },
                location: { S: event.location },
                isFlagged: { BOOL: event.isFlagged }
            }
        };

        await dynamoDB.send(new PutItemCommand(params));

        return {
            statusCode: 200,
            body: JSON.stringify({ message: "Call Data Stored", callID })
        };
    } catch (error) {
        return {
            statusCode: 500,
            body: JSON.stringify({ error: error.message })
        };
    }
};
```

### 4. Create the DynamoDB Table
Run the following command to create the DynamoDB table with necessary attributes and indexes:

```sh
aws dynamodb create-table \
    --table-name TelecomCalls \
    --attribute-definitions \
        AttributeName=phoneNumber,AttributeType=S \
        AttributeName=timestamp,AttributeType=S \
        AttributeName=callType,AttributeType=S \
        AttributeName=location,AttributeType=S \
        AttributeName=isFlagged,AttributeType=B \
    --key-schema \
        AttributeName=phoneNumber,KeyType=HASH \
        AttributeName=timestamp,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --global-secondary-indexes '[
        {
            "IndexName": "CallTypeIndex",
            "KeySchema": [
                {"AttributeName": "callType", "KeyType": "HASH"},
                {"AttributeName": "timestamp", "KeyType": "RANGE"}
            ],
            "Projection": {"ProjectionType": "ALL"}
        },
        {
            "IndexName": "LocationIndex",
            "KeySchema": [
                {"AttributeName": "location", "KeyType": "HASH"},
                {"AttributeName": "timestamp", "KeyType": "RANGE"}
            ],
            "Projection": {"ProjectionType": "ALL"}
        },
        {
            "IndexName": "FlaggedCallsIndex",
            "KeySchema": [
                {"AttributeName": "isFlagged", "KeyType": "HASH"},
                {"AttributeName": "timestamp", "KeyType": "RANGE"}
            ],
            "Projection": {"ProjectionType": "ALL"}
        }
    ]'
```

### Create IAM Role

Attach Trust Policy

```sh
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
```

### Create the Lambda Function
```sh
aws lambda create-function --function-name TelecomFraudDetector \
    --runtime nodejs18.x \
    --role arn:aws:iam::522424656191:role/LambdaDynamoDBRole  \
    --handler index.handler \
    --timeout 15 \
    --memory-size 256 \
    --zip-file fileb://lambda_function.zip
```


### 5. Deploy the Lambda Function
Zip your code and upload it to AWS Lambda or use AWS CLI:
```sh
zip function.zip index.js
aws lambda update-function-code --function-name TelecomFraudDetector --zip-file fileb://function.zip
```

## Phase 2: Enhancements

### 1. Expanding Data Attributes
- Added `callType`, `location`, and `isFlagged` attributes to track more details about each call.
- Updated the Lambda function to store these attributes.

### 2. Implementing Global Secondary Indexes
- Created **CallTypeIndex**, **LocationIndex**, and **FlaggedCallsIndex** to allow efficient querying based on these attributes.

### 3. Testing & Verification

Use the following test event:

``` sh
{
    "phoneNumber": "+14165551234",
    "callDuration": 120,
    "riskScore": 85
}
```

If the test is successful, the response should look like:

``` sh
{
  "statusCode": 200,
  "body": "{\"message\": \"Call Data Stored\", \"callID\": \"some-uuid\", \"timestamp\": \"2025-03-31T20:15:00.123Z\"}"
}
``` 

- Verified that queries against the new indexes return expected results.

## Conclusion
This project successfully implements a fraud detection system for telecom call records using AWS. The enhancements in Phase 2 improve data structuring and querying capabilities.

### Future Enhancements
- Implement AI-based fraud detection.
- Add real-time alerting mechanisms.
- Improve visualization for fraud reports.

---
For any issues, feel free to open a GitHub issue or reach out!

