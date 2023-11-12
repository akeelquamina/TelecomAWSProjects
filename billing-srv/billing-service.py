# Import necessary libraries
from flask import Flask, jsonify

# Create Flask application
app = Flask(__name__)

# Endpoint to get billing information for a call
@app.route('/billing/<int:call_id>', methods=['GET'])
def get_billing_info(call_id):
    # Perform billing logic (replace with industry standards)
    # For simplicity, just returning a sample billing information
    return jsonify({'call_id': call_id, 'amount': 10.5, 'currency': 'USD'}), 200

# Main entry point of the application
if __name__ == '__main__':
    # Run the application on port 5002
    app.run(host='0.0.0.0', port=5002)
