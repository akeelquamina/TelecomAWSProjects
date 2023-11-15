from flask import Flask, jsonify, request

app = Flask(__name__)

# Dummy database for storing call routing preferences
call_routing_preferences = {'user1': 'Route A', 'user2': 'Route B', 'user3': 'Route C'}

@app.route('/route-call', methods=['POST'])
def route_call():
    data = request.get_json()
    user_id = data.get('user_id')

    if not user_id:
        return jsonify({'error': 'Invalid request'}), 400

    if user_id not in call_routing_preferences:
        return jsonify({'error': 'User not found'}), 404

    routing_preference = call_routing_preferences[user_id]
    return jsonify({'message': f'Call routed via {routing_preference} for user {user_id}'})

if __name__ == '__main__':
    app.run(debug=True, port=5003)
