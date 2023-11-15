# sms_notification_service.py
from flask import Flask, jsonify, request
import requests

app = Flask(__name__)

# Dummy database for storing notification preferences
notification_preferences = {'user1': 'SMS', 'user2': 'Email', 'user3': 'SMS'}

# URL of the Billing Service
billing_service_url = "http://billing-service:5001/charge-user"

# URL of the Call Routing Service
call_routing_service_url = "http://call-routing-service:5002/route-call"

@app.route('/send-notification', methods=['POST'])
def send_notification():
    data = request.get_json()
    user_id = data.get('user_id')

    if not user_id:
        return jsonify({'error': 'Invalid request'}), 400

    if user_id not in notification_preferences:
        return jsonify({'error': 'User not found'}), 404

    notification_preference = notification_preferences[user_id]

    # Make an HTTP request to the Billing Service
    response_billing = requests.post(billing_service_url, json={'user_id': user_id, 'notification_preference': notification_preference})

    # Make an HTTP request to the Call Routing Service
    response_routing = requests.post(call_routing_service_url, json={'user_id': user_id})

    return jsonify({'message': f'Notification sent via {notification_preference} and call routed for user {user_id} successfully'})


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
