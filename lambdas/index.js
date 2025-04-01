const { DynamoDBClient, PutItemCommand } = require("@aws-sdk/client-dynamodb");
const { v4: uuidv4 } = require("uuid");

const dynamoDB = new DynamoDBClient({ region: "us-east-2" });

exports.handler = async (event) => {
    try {
        const callID = uuidv4(); // Partition Key
        const timestamp = Date.now().toString(); // Ensure unique Sort Key (Epoch time in ms)

        console.log("Generated callID:", callID);
        console.log("Generated timestamp:", timestamp);

        const params = {
            TableName: process.env.TABLE_NAME || "TelecomCalls",
            Item: {
                callID: { S: callID }, // Partition Key
                timestamp: { S: timestamp }, // Sort Key (MUST be a unique number)
                phoneNumber: { S: String(event.phoneNumber) }, // Ensure string format
                callDuration: { N: event.callDuration.toString() }, // Convert to string
                riskScore: { N: event.riskScore.toString() } // Convert to string
            }
        };

        console.log("DynamoDB Params:", JSON.stringify(params, null, 2)); // Debugging log

        await dynamoDB.send(new PutItemCommand(params));

        return {
            statusCode: 200,
            body: JSON.stringify({ message: "Call Data Stored", callID, timestamp })
        };
    } catch (error) {
        console.error("Error:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: error.message })
        };
    }
};
