import os
from flask import Flask, request, jsonify
from datetime import datetime

app = Flask(__name__)
UPLOAD_FOLDER = 'uploads'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'image' not in request.files:
        return jsonify({'error': 'No image file provided'}), 400
    
    file = request.files['image']
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400
        
    if file:
        filename = f"capture_{datetime.now().strftime('%Y%m%d_%H%M%S')}.jpg"
        filepath = os.path.join(UPLOAD_FOLDER, filename)
        file.save(filepath)
        print(f"✅ Received and saved image: {filepath}")
        return jsonify({'success': True, 'message': 'File uploaded successfully', 'path': filepath}), 200

@app.route('/upload_json', methods=['POST'])
def upload_json():
    data = request.json
    if not data:
        return jsonify({'error': 'No JSON data provided'}), 400
    
    filename = data.get('filename', 'unknown')
    # Save the json with the same name as the original image but .json extension
    json_filename = f"{filename}_aura.json"
    filepath = os.path.join(UPLOAD_FOLDER, json_filename)
    
    import json
    with open(filepath, 'w') as f:
        json.dump(data, f, indent=4)
        
    print(f"✅ Received and saved JSON dataset: {filepath}")
    return jsonify({'success': True, 'message': 'JSON saved successfully'}), 200

if __name__ == '__main__':
    # Listen on all network interfaces so the phone can connect
    print("🚀 Server started! Listening for images on your local network...")
    print("Make sure your phone is on the same WiFi network as this laptop.")
    app.run(host='0.0.0.0', port=5000)
