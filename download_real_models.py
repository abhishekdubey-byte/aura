import os
import urllib.request

os.makedirs('assets/models', exist_ok=True)

print("Downloading real NSFW model (MobileNetV2 from nsfwjs)...")
try:
    urllib.request.urlretrieve(
        'https://raw.githubusercontent.com/GantMan/nsfw_model/master/tflite/nsfw.tflite',
        'assets/models/nsfw.tflite'
    )
    print("Downloaded nsfw.tflite")
except Exception as e:
    print(f"Failed to download NSFW model: {e}")

print("Downloading real Emotion model (FER2013 MiniXception)...")
try:
    urllib.request.urlretrieve(
        'https://raw.githubusercontent.com/atulapra/Emotion-detection/master/models/model_v6_23.hdf5',
        'assets/models/emotion.hdf5'
    )
    # The direct TFLite file might be hard to find reliably without conversion, but there are some on HF.
    # We will try a known public huggingface repo for emotion tflite
    urllib.request.urlretrieve(
        'https://huggingface.co/mrm8488/fer2013-minixception-tflite/resolve/main/model.tflite',
        'assets/models/emotion.tflite'
    )
    print("Downloaded emotion.tflite")
except Exception as e:
    print(f"Failed to download Emotion model: {e}")
