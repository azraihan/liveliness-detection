"""
Convert SpoofNet PyTorch model to TorchScript Lite (.ptl) format for mobile deployment
"""

import torch
import torch.nn as nn
from torchvision.models import mobilenet_v2
import os


class SpoofNet(nn.Module):
    """
    Face Anti-Spoofing model based on MobileNetV2
    """
    def __init__(self):
        super(SpoofNet, self).__init__()
        # Load pretrained MobileNetV2
        self.pretrained_net = mobilenet_v2(pretrained=True)
        self.features = self.pretrained_net.features

        # Adding the extra layers
        self.conv2d = nn.Conv2d(1280, 32, kernel_size=(3, 3), padding=1)
        self.relu = nn.ReLU()
        self.dropout1 = nn.Dropout(0.2)
        self.global_avg_pool = nn.AdaptiveAvgPool2d((1, 1))
        self.fc = nn.Linear(32, 1)
        self.sigmoid = nn.Sigmoid()

    def forward(self, x):
        x = self.features(x)
        x = self.conv2d(x)
        x = self.relu(x)
        x = self.dropout1(x)
        x = self.global_avg_pool(x)
        x = torch.flatten(x, 1)
        x = self.fc(x)
        x = self.sigmoid(x)
        return x


def convert_model(model_path, output_path):
    """
    Convert PyTorch model to TorchScript Lite format
    """
    print(f"Loading model from: {model_path}")

    # Initialize model architecture
    model = SpoofNet()

    # Load checkpoint
    checkpoint = torch.load(model_path, map_location='cpu')

    # Extract state dict from checkpoint
    if isinstance(checkpoint, dict) and 'state_dict' in checkpoint:
        model.load_state_dict(checkpoint['state_dict'])
        print("Loaded from checkpoint with 'state_dict' key")
    else:
        model.load_state_dict(checkpoint)
        print("Loaded state dict directly")

    model.eval()

    # Create example input (batch=1, channels=3, height=224, width=224)
    example_input = torch.rand(1, 3, 224, 224)

    # Test forward pass
    with torch.no_grad():
        test_output = model(example_input)
        print(f"Test output shape: {test_output.shape}")
        print(f"Test output value: {test_output.item():.4f}")

    # Trace the model
    print("Tracing model...")
    traced_model = torch.jit.trace(model, example_input)

    # Optimize for mobile
    print("Optimizing for mobile...")
    from torch.utils.mobile_optimizer import optimize_for_mobile
    optimized_model = optimize_for_mobile(traced_model)

    # Save as .ptl format (for flutter_pytorch_lite package)
    print(f"Saving to: {output_path}")
    optimized_model._save_for_lite_interpreter(output_path)

    # Verify the saved model
    file_size = os.path.getsize(output_path) / (1024 * 1024)
    print(f"Model saved successfully!")
    print(f"File size: {file_size:.2f} MB")

    return output_path


if __name__ == "__main__":
    model_path = "mobilenetv2-best.pt"
    output_path = "mobilenetv2_mobile.ptl"

    if not os.path.exists(model_path):
        print(f"Error: Model file not found: {model_path}")
        exit(1)

    convert_model(model_path, output_path)
    print("\nConversion complete!")
    print(f"Use '{output_path}' in your Flutter app")
