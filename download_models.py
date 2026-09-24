import urllib.request
import zipfile
import os

os.makedirs('assets/models', exist_ok=True)
print("Downloading MobileNet SSD for object/clothing detection...")
urllib.request.urlretrieve(
    'https://storage.googleapis.com/download.tensorflow.org/models/tflite/coco_ssd_mobilenet_v1_1.0_quant_2018_06_29.zip',
    'assets/models/ssd.zip'
)
with zipfile.ZipFile('assets/models/ssd.zip', 'r') as zip_ref:
    zip_ref.extractall('assets/models/')
os.remove('assets/models/ssd.zip')
print("Extracted MobileNet SSD.")
