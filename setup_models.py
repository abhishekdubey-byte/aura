import os
import urllib.request
import zipfile
import numpy as np
import tensorflow as tf

def download_ssd():
    os.makedirs('assets/models', exist_ok=True)
    print("Downloading MobileNet SSD for object/clothing detection...")
    try:
        urllib.request.urlretrieve(
            'https://storage.googleapis.com/download.tensorflow.org/models/tflite/coco_ssd_mobilenet_v1_1.0_quant_2018_06_29.zip',
            'assets/models/ssd.zip'
        )
        with zipfile.ZipFile('assets/models/ssd.zip', 'r') as zip_ref:
            zip_ref.extractall('assets/models/')
        os.remove('assets/models/ssd.zip')
        
        # Rename for simplicity
        os.rename('assets/models/detect.tflite', 'assets/models/ssd.tflite')
        os.rename('assets/models/labelmap.txt', 'assets/models/ssd_labels.txt')
        print("Successfully downloaded and extracted MobileNet SSD.")
    except Exception as e:
        print(f"Failed to download SSD: {e}")

def create_dummy_model(name, input_shape, num_classes):
    print(f"Creating placeholder {name} model...")
    model = tf.keras.Sequential([
        tf.keras.layers.InputLayer(input_shape=input_shape),
        tf.keras.layers.Flatten(),
        tf.keras.layers.Dense(num_classes, activation='softmax')
    ])
    
    # Convert to TFLite
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_model = converter.convert()
    
    with open(f'assets/models/{name}.tflite', 'wb') as f:
        f.write(tflite_model)
    print(f"Created {name}.tflite successfully.")

if __name__ == "__main__":
    download_ssd()
    # Emotion: usually 48x48 grayscale or 224x224 RGB, outputting 7 classes (Angry, Disgust, Fear, Happy, Sad, Surprise, Neutral)
    create_dummy_model('emotion', (48, 48, 1), 7)
    # NSFW: usually 224x224 RGB, outputting 5 classes (Drawings, Hentai, Neutral, Porn, Sexy)
    create_dummy_model('nsfw', (224, 224, 3), 5)
    
    print("\nAll models are ready in assets/models/!")
    print("Note: The emotion and nsfw models are lightweight structural placeholders.")
    print("You can replace them with real trained models (like from Kaggle) later, and the app will process them perfectly!")
