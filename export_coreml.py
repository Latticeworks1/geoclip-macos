

import torch
import coremltools as ct
import numpy as np
from geoclip import GeoCLIP
import os

def export_image_encoder_to_coreml():
    """
    Loads the pretrained GeoCLIP model, traces its ImageEncoder,
    and converts it to a Core ML model file.
    """
    print("Initializing GeoCLIP model with PyTorch backend...")
    # Load the pretrained model using the PyTorch backend
    model = GeoCLIP(from_pretrained=True, backend='torch')
    model.eval()

    # Isolate the image encoder
    image_encoder = model.image_encoder
    
    # The image encoder's preprocess method handles image loading and transformation.
    # For tracing, we need a sample tensor that matches the model's input.
    # The CLIP ViT-B/32 model expects a (1, 3, 224, 224) tensor.
    dummy_input = torch.rand(1, 3, 224, 224)

    print("Tracing the ImageEncoder model...")
    # Trace the model with a dummy input
    traced_model = torch.jit.trace(image_encoder, dummy_input)

    print("Converting the traced model to Core ML format...")
    # Use TensorType instead of ImageType - we'll handle preprocessing in Swift
    # This avoids Core ML's automatic preprocessing which can cause shape issues
    coreml_model = ct.convert(
        traced_model,
        convert_to="mlprogram",
        inputs=[ct.TensorType(name="image_input", shape=dummy_input.shape)],
        compute_units=ct.ComputeUnit.ALL,
    )

    output_filename = "ImageEncoder.mlpackage"
    print(f"Saving the Core ML model to {output_filename}...")
    coreml_model.save(output_filename)

    print(f"\nSuccessfully exported the model to {os.path.abspath(output_filename)}")
    print("You can now add this .mlmodel file to your Xcode project.")
    print("\nModel details:")
    print(f"Input: {coreml_model.input_description}")
    print(f"Output: {coreml_model.output_description}")


def export_location_encoder_to_coreml():
    """
    Loads the pretrained GeoCLIP model, traces its LocationEncoder,
    and converts it to a Core ML model file.
    """
    print("\nInitializing LocationEncoder model with PyTorch backend...")
    # Load the pretrained model using the PyTorch backend
    model = GeoCLIP(from_pretrained=True, backend='torch')
    model.eval()

    # Isolate the location encoder
    location_encoder = model.location_encoder
    
    # The location encoder expects a batch of GPS coordinates, e.g., (1, 2) for a single pair.
    dummy_input = torch.rand(1, 2)

    print("Tracing the LocationEncoder model...")
    # Trace the model with a dummy input
    traced_model = torch.jit.trace(location_encoder, dummy_input)

    print("Converting the traced model to Core ML format...")
    # Convert to Core ML using the Unified Conversion API
    coreml_model = ct.convert(
        traced_model,
        convert_to="mlprogram",
        inputs=[ct.TensorType(name="gps_input", shape=dummy_input.shape)],
        compute_units=ct.ComputeUnit.ALL,
    )

    output_filename = "LocationEncoder.mlpackage"
    print(f"Saving the Core ML model to {output_filename}...")
    coreml_model.save(output_filename)

    print(f"\nSuccessfully exported the model to {os.path.abspath(output_filename)}")
    print("\nModel details:")
    print(f"Input: {coreml_model.input_description}")
    print(f"Output: {coreml_model.output_description}")


if __name__ == "__main__":
    export_image_encoder_to_coreml()
    export_location_encoder_to_coreml()

