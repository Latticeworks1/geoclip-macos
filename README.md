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

## Quick Start

All required files (Core ML models and pre-computed features) are included via Git LFS. Just clone and build!

### 1. Clone Repository

```bash
git clone https://github.com/Latticeworks1/geoclip-macos.git
cd geoclip-macos
```

Make sure you have Git LFS installed to download the large model files:
```bash
# Install Git LFS if needed
brew install git-lfs
git lfs install
git lfs pull  # Download large files
```

### 2. Build and Run


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
