# Telecom Fraud Detection with AWS Lambda

## Overview
This project implements a **Telecom Fraud Detection System** using **AWS Lambda**, **DynamoDB**, and **AWS SDK for Node.js**. The system ingests call data and stores it in a DynamoDB table for further analysis.

## Architecture
- **AWS Lambda**: Processes incoming call data.
- **DynamoDB**: Stores call records for further fraud detection.
- **IAM Role**: Grants Lambda permissions to write to DynamoDB.

## Prerequisites
1. **AWS CLI Installed & Configured**
2. **Node.js Installed**
3. **DynamoDB Table Setup**
   - Table Name: `TelecomCalls`
   - Partition Key: `callID (S)`
   - Sort Key: `timestamp (N)`

## Setup & Deployment
### 1. Install Dependencies
Navigate to the `lambdas` directory and run:
```sh
npm install @aws-sdk/client-dynamodb uuid
```

### 2. Create the Lambda Function
#### **Lambda Code (`index.js`)**
```javascript
const { DynamoDBClient, PutItemCommand } = require("@aws-sdk/client-dynamodb");
const { v4: uuidv4 } = require("uuid");

const dynamoDB = new DynamoDBClient({ region: "us-east-2" });

exports.handler = async (event) => {
    try {
        const callID = uuidv4();
        const timestamp = Date.now().toString();

        const params = {
            TableName: process.env.TABLE_NAME || "TelecomCalls",
            Item: {
                callID: { S: callID },
                timestamp: { N: timestamp },
                phoneNumber: { S: String(event.phoneNumber) },
                callDuration: { N: event.callDuration.toString() },
                riskScore: { N: event.riskScore.toString() }
            }
        };

        await dynamoDB.send(new PutItemCommand(params));
        return { statusCode: 200, body: JSON.stringify({ message: "Call Data Stored", callID, timestamp }) };
    } catch (error) {
        return { statusCode: 500, body: JSON.stringify({ error: error.message }) };
    }
};
```

### 3. Package the Code
```sh
zip -r lambda_function.zip index.js node_modules package.json
```

### 4. Deploy to AWS Lambda
```sh
aws lambda create-function --function-name TelecomFraudDetector \
    --runtime nodejs18.x \
    --role arn:aws:iam::YOUR_ACCOUNT_ID:role/LambdaDynamoDBRole \
    --handler index.handler \
    --timeout 15 \
    --memory-size 256 \
    --zip-file fileb://lambda_function.zip
```

### 5. Test the Function
Create a `test-event.json` file:
```json
{
    "phoneNumber": "+1234567890",
    "callDuration": 300,
    "riskScore": 0.8
}
```
Run the test:
```sh
aws lambda invoke --function-name TelecomFraudDetector output.json --payload file://test-event.json
```
Check `output.json` for the response.

## Next Steps
- Implement fraud detection logic.
- Integrate with a notification system (SNS, SES, or an alerting dashboard).
- Expand functionality with data analysis tools (Amazon Athena, QuickSight).

---
### Author
**[Your Name]** - Cloud & Cybersecurity Enthusiast

