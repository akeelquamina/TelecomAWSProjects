from flask import Flask, jsonify, request

app = Flask(__name__)

# Dummy database for storing routing information
routing_info = {'user1': 'route1', 'user2': 'route2', 'user3': 'route1'}


@app.route('/call-routing', methods=['POST'])
def route_call():
    data = request.get_json()

    user_id = data.get('user_id')

    if not user_id:
        return jsonify({'error': 'Invalid request'}), 400

    if user_id not in routing_info:
        return jsonify({'error': 'User not found'}), 404

    route = routing_info[user_id]

    return jsonify({'message': f'Call routed through {route} for user {user_id} successfully'})


if __name__ == '__main__':
    app.run(debug=True)
