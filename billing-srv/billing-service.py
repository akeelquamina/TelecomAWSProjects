from flask import Flask, jsonify, request

app = Flask(__name__)

# Dummy database for storing user balances
user_balances = {'user1': 100, 'user2': 50, 'user3': 200}


@app.route('/billing', methods=['POST'])
def charge_user():
    data = request.get_json()

    user_id = data.get('user_id')
    amount = data.get('amount')

    if not user_id or not amount:
        return jsonify({'error': 'Invalid request'}), 400

    if user_id not in user_balances:
        return jsonify({'error': 'User not found'}), 404

    current_balance = user_balances[user_id]

    if current_balance < amount:
        return jsonify({'error': 'Insufficient funds'}), 403

    user_balances[user_id] -= amount

    return jsonify({'message': f'Charged {amount} to user {user_id} successfully'})


if __name__ == '__main__':
    app.run(debug=True)
