import websocket
import json
import threading

def on_message(ws, message):
    print("Received message:")
    print(message)
    # Optionally, save the message to a file for analysis
    with open('./gaiad_messages.log', 'a') as file:
        file.write(message + '\n')

def on_error(ws, error):
    print("Error:")
    print(error)

def on_close(ws):
    print("### closed ###")

def on_open(ws):
    print("WebSocket connection opened.")
    # Subscribe to all messages for broad capture; adjust as needed for specific subscriptions
    subscribe_message = json.dumps({
        "jsonrpc": "2.0",
        "method": "subscribe",
        "params": ["tm.event = 'NewBlock'"],
        "id": 1
    })
    ws.send(subscribe_message)

if __name__ == "__main__":
    websocket.enableTrace(True)
    ws_url = 'ws://localhost:26657/websocket'  # Ensure this is the correct URL for your Gaiad node
    ws = websocket.WebSocketApp(ws_url,
                                on_open=on_open,
                                on_message=on_message,
                                on_error=on_error,
                                on_close=on_close)
    wst = threading.Thread(target=ws.run_forever)
    wst.start()
