# Import necessary libraries
from flask import Flask, request, jsonify

# Create Flask application
app = Flask(__name__)

# Endpoint to initiate a call
@app.route('/calls/initiate', methods=['POST'])
def initiate_call():
    data = request.json

    # Extract necessary information from the request
    caller = data.get('caller')
    callee = data.get('callee')

    # Perform call initiation logic (replace with industry standards)
    # For simplicity, just returning a success message
    return jsonify({'message': 'Call initiated successfully', 'caller': caller, 'callee': callee}), 201

# Main entry point of the application
if __name__ == '__main__':
    # Run the application on port 5000
    app.run(host='0.0.0.0', port=5000)
