# call_routing_service.py
from flask import Flask, jsonify, request

app = Flask(__name__)

# Dummy logic for call routing
def route_call(user_id):
    # Logic for call routing based on user_id
    # ...

    return f'Call routed successfully for user {user_id}'

@app.route('/route-call', methods=['POST'])
def route_call_endpoint():
    data = request.get_json()
    user_id = data.get('user_id')

    if not user_id:
        return jsonify({'error': 'Invalid request'}), 400

    return jsonify({'message': route_call(user_id)})


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5002)
