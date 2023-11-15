# billing_service.py
from flask import Flask, jsonify, request

app = Flask(__name__)

# Dummy database for storing user balances
user_balances = {'user1': 100, 'user2': 50, 'user3': 200}

@app.route('/charge-user', methods=['POST'])
def charge_user():
    data = request.get_json()
    user_id = data.get('user_id')
    notification_preference = data.get('notification_preference')

    if not user_id:
        return jsonify({'error': 'Invalid request'}), 400

    if user_id not in user_balances:
        return jsonify({'error': 'User not found'}), 404

    current_balance = user_balances[user_id]

    # Charge the user based on notification preference logic
    # ...

    return jsonify({'message': f'Charged user {user_id} successfully'})


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5001)
