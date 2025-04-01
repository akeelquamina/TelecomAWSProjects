# Telecom Fraud Detection with AWS

## Overview
This project focuses on building a Telecom Fraud Detection System using AWS services. The system detects anomalies in call patterns and stores relevant data in DynamoDB for analysis. The development was divided into two phases:

- **Phase 1:** Setting up the Lambda function to store call data in DynamoDB.
- **Phase 2:** Enhancing the system with anomaly detection and debugging issues encountered during deployment.

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
                timestamp: { S: new Date().toISOString() } // Required as sort key
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

### 4. Deploy the Lambda Function
Zip your code and upload it to AWS Lambda or use AWS CLI:
```sh
zip function.zip index.js
aws lambda update-function-code --function-name TelecomFraudDetector --zip-file fileb://function.zip
```

## Phase 2: Debugging & Enhancements

### 1. Resolving "Cannot use import statement outside a module"
- Convert the file to ES module by updating `package.json`:
```json
{
  "type": "module"
}
```

### 2. Handling Missing Sort Key (Timestamp)
- The `timestamp` field was required in the DynamoDB table as a sort key. Ensure it's included in the Lambda function.

### 3. Fixing GitHub Push Protection Errors
If a secret is detected during `git push`, follow these steps:
```sh
git rev-list --objects --all | grep blobid  # Find the file containing the secret
git filter-branch --force --index-filter 'git rm --cached --ignore-unmatch path/to/file' --prune-empty --tag-name-filter cat -- --all
git push origin --force
```

### 4. Resolving "fatal: 'origin' does not appear to be a git repository"
Ensure the correct remote is set:
```sh
git remote -v  # Check remotes
git remote add origin https://github.com/yourusername/TelecomAWSProjects.git
git push origin telecom-fraud-detector --force
```

## Conclusion
This project successfully implements a fraud detection system for telecom call records using AWS. The debugging process and solutions documented here will help in maintaining and expanding the system.

### Future Enhancements
- Implement AI-based fraud detection.
- Add real-time alerting mechanisms.
- Improve visualization for fraud reports.

---
For any issues, feel free to open a GitHub issue or reach out!

