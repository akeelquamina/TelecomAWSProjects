from flask import Flask, jsonify, request

app = Flask(__name__)

# Dummy database for storing notification preferences
notification_preferences = {'user1': 'SMS', 'user2': 'Email', 'user3': 'SMS'}

@app.route('/send-notification', methods=['POST'])
def send_notification():
    data = request.get_json()
    user_id = data.get('user_id')

    if not user_id:
        return jsonify({'error': 'Invalid request'}), 400

    if user_id not in notification_preferences:
        return jsonify({'error': 'User not found'}), 404

    notification_preference = notification_preferences[user_id]
    return jsonify({'message': f'Notification sent via {notification_preference} to user {user_id} successfully'})

if __name__ == '__main__':
    app.run(debug=True, port=5001)
