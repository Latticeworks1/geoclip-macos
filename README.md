# GeoCLIP macOS - Native Core ML Image Geolocalization

Native macOS app for worldwide image geolocalization using GeoCLIP. Powered by Core ML for fast, on-device inference with Apple Silicon acceleration.

## Features

- **Pure Swift/Core ML** - No Python dependencies required
- **Apple Silicon optimized** - Uses Neural Engine for acceleration
- **Fast inference** - Sub-second predictions on 100K location gallery
- **Drag & drop** - Simple interface for testing images
- **Interactive map** - View top predictions on an integrated map

## Requirements

- macOS 13.0+
- Xcode 15.0+
- ~200MB disk space for pre-computed gallery features

## Important Note

The pre-computed gallery features file (`gps_gallery_features.bin`, 196MB) is **not included** in this repo due to size. You must generate it yourself (see step 2 below).

## Quick Start

### 1. Export Core ML Models

First, you need the original GeoCLIP weights and export them to Core ML:

```bash
# Install dependencies
pip install torch coremltools geoclip

# Export models (creates ImageEncoder.mlpackage and LocationEncoder.mlpackage)
python export_coreml.py
```

This will create:
- `ImageEncoder.mlpackage` - CLIP vision encoder + MLP projection (frozen CLIP weights)
- `LocationEncoder.mlpackage` - Multi-scale RFF location encoder

### 2. Generate Gallery Features

The app uses pre-computed features for 100K worldwide locations for fast inference:

```python
import torch
import numpy as np
from geoclip import GeoCLIP
import struct

# Load model
model = GeoCLIP(from_pretrained=True, backend='torch')
model.eval()

# Load GPS gallery
import pandas as pd
gps_gallery = pd.read_csv(
    'path/to/geoclip/model/gps_gallery/coordinates_100K.csv'
)

# Encode all locations
with torch.no_grad():
    gps_tensor = torch.tensor(gps_gallery[['LAT', 'LON']].values, dtype=torch.float32)
    location_features = model.location_encoder(gps_tensor).numpy()

# Save as binary file
with open('GeoCLIP.app/gps_gallery_features.bin', 'wb') as f:
    f.write(struct.pack('i', len(gps_gallery)))  # Gallery size
    for _, row in gps_gallery.iterrows():
        f.write(struct.pack('ff', row['LAT'], row['LON']))  # GPS coords
    location_features.astype(np.float32).tofile(f)  # Features

print(f"Saved {len(gps_gallery)} pre-computed features")
```

### 3. Build and Run

```bash
cd GeoCLIP.app
xcodebuild -project GeoCLIP.xcodeproj -configuration Debug build
open build/Debug/GeoCLIP.app
```

Or open `GeoCLIP.xcodeproj` in Xcode and hit Run.

## Usage

1. Launch the app
2. Wait for "Ready" status (models and gallery loading)
3. Drag & drop an image or click "Select Image"
4. Choose number of results (1, 3, 5, or 10)
5. Click "Predict Location"
6. View predictions on the map

## Architecture

### Core ML Models

**ImageEncoder**
- Input: `image_input` - Float32 tensor [1, 3, 224, 224] (NCHW, CLIP-normalized)
- Output: `var_2059` - Float32 tensor [1, 512] (image features)
- Architecture: Frozen CLIP ViT-L/14 + trainable MLP (768→768→512)

**LocationEncoder** (not used in app, features are pre-computed)
- Input: `gps_input` - Float32 tensor [1, 2] (lat, lon)
- Output: `var_222` - Float32 tensor [1, 512] (location features)
- Architecture: Multi-scale RFF + 3-layer MLPs

### Image Preprocessing

Images are preprocessed to match CLIP's expected input:

1. Resize to 224×224 (maintains aspect ratio, center crop)
2. Convert to RGB float values [0, 1]
3. Normalize with CLIP statistics:
   - Mean: `[0.48145466, 0.4578275, 0.40821073]`
   - Std: `[0.26862954, 0.26130258, 0.27577711]`
4. Arrange in NCHW format (batch, channels, height, width)

### Inference Pipeline

```
Image → Preprocess → ImageEncoder → Normalize Features
                                          ↓
Gallery GPS ← Top-K ← Softmax ← Cosine Similarity → Pre-normalized Gallery Features
```

1. **Load gallery** (once at startup): Read 100K GPS coordinates and pre-computed features, normalize all features
2. **Encode image**: Convert image to tensor, run through ImageEncoder Core ML model
3. **Normalize**: L2-normalize the 512-dim image feature vector
4. **Similarity**: Compute cosine similarity with all 100K normalized gallery features
5. **Softmax**: Apply softmax to get probability distribution
6. **Top-K**: Return K locations with highest probabilities

## Performance

- **Gallery load time**: ~2-3 seconds (one-time at startup)
- **Inference time**: ~0.01-0.05 seconds per image
  - Image encoding: ~0.005s
  - Similarity computation: ~0.005s (100K × 512 dot products)
- **Memory**: ~200MB for gallery features

## Project Structure

```
GeoCLIP.app/
├── GeoCLIP.xcodeproj/          # Xcode project
├── SwiftUI/
│   ├── GeoCLIPApp.swift        # App entry point
│   ├── ContentView.swift       # Main UI
│   ├── GeoCLIPCoreML.swift     # Core ML inference engine
│   └── SettingsView.swift      # Settings UI
├── GeoCLIP-Info.plist          # App metadata
├── GeoCLIP.entitlements        # Sandboxing permissions
├── ImageEncoder.mlpackage/     # Core ML image encoder
├── LocationEncoder.mlpackage/  # Core ML location encoder (unused)
└── gps_gallery_features.bin    # Pre-computed gallery features (206MB)
```

## Technical Details

### Binary Format (gps_gallery_features.bin)

```
[4 bytes]              Gallery size (int32)
[8 bytes × N]          GPS coordinates (N × [float32 lat, float32 lon])
[4 bytes × N × 512]    Pre-computed features (N × 512 × float32)
```

### Feature Normalization

Both image and gallery features are L2-normalized before computing cosine similarity:

```swift
norm = sqrt(Σ(features²))
normalized = features / norm
similarity = dot(normalized_image, normalized_gallery)
```

This ensures rotation-invariant similarity in the embedding space.

## Troubleshooting

**App crashes on launch**
- Ensure `gps_gallery_features.bin` is in the app bundle Resources
- Check that Core ML models are properly signed and included

**Predictions are incorrect**
- Verify image preprocessing matches CLIP normalization
- Ensure gallery features were generated with the same model weights
- Check that both image and gallery features are L2-normalized

**Slow performance**
- Gallery features should be pre-normalized at load time (not per prediction)
- Use Neural Engine compute units in MLModelConfiguration
- Avoid normalizing gallery features inside the similarity loop

## Credits

Based on [GeoCLIP](https://github.com/VicenteVivan/geo-clip) by Vicente Vivanco Cepeda et al.

**Paper**: [GeoCLIP: Clip-Inspired Alignment between Locations and Images for Effective Worldwide Geo-localization](https://arxiv.org/abs/2309.16020) (NeurIPS 2023)

## License

See the original [GeoCLIP repository](https://github.com/VicenteVivan/geo-clip) for license information.
