"""
Memory Profiler for MobileNetV2 Face Anti-Spoofing Model
Profiles ONLY the model requirements for mobile deployment
"""

import torch
import torch.nn as nn
from torchvision.models import mobilenet_v2
import torchvision.transforms as transforms
from PIL import Image
import numpy as np
from memory_profiler import profile
import psutil
import os


class SpoofNet(nn.Module):
    """Face Anti-Spoofing model based on MobileNetV2"""
    def __init__(self):
        super(SpoofNet, self).__init__()
        self.pretrained_net = mobilenet_v2(pretrained=True)
        self.features = self.pretrained_net.features
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


def model_memory_mb(model):
    """Calculate model parameter and buffer memory"""
    param_mem = sum(p.numel() * p.element_size() for p in model.parameters())
    buffer_mem = sum(b.numel() * b.element_size() for b in model.buffers())
    return (param_mem + buffer_mem) / 1024**2


def ram_mb():
    """Get current process RAM"""
    process = psutil.Process(os.getpid())
    return process.memory_info().rss / 1024**2


def get_transform():
    """Image transformations for inference"""
    return transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], 
                           std=[0.229, 0.224, 0.225])
    ])


@profile
def initialize_model(model_path):
    """Profile: Load model from checkpoint"""
    print("\n[PROFILING] Loading model...")
    model = SpoofNet()
    
    checkpoint = torch.load(model_path, map_location='cpu')
    if isinstance(checkpoint, dict) and 'state_dict' in checkpoint:
        model.load_state_dict(checkpoint['state_dict'])
    else:
        model.load_state_dict(checkpoint)
    
    model.eval()
    return model


@profile
def prepare_input_tensor():
    """Profile: Create input tensor (simulating preprocessed image)"""
    print("\n[PROFILING] Creating input tensor...")
    # Simulate a 224x224 RGB image
    dummy_image = np.random.randint(0, 255, (224, 224, 3), dtype=np.uint8)
    pil_image = Image.fromarray(dummy_image)
    
    transform = get_transform()
    tensor = transform(pil_image)
    tensor = tensor.unsqueeze(0)  # Add batch dimension
    
    return tensor


@profile
def run_inference(model, input_tensor):
    """Profile: Run single inference pass"""
    print("\n[PROFILING] Running inference...")
    with torch.inference_mode():
        output = model(input_tensor)
    return output


def print_separator(title):
    """Print formatted separator"""
    print("\n" + "="*70)
    print(f"  {title}")
    print("="*70)


def main():
    model_path = 'mobilenetv2-best.pt'
    
    print_separator("MEMORY PROFILE: MobileNetV2 Face Anti-Spoofing")
    print("Purpose: Determine minimum memory requirements for mobile deployment")
    print("="*70)
    
    # Baseline memory
    baseline_ram = ram_mb()
    print(f"\n[BASELINE] Python process RAM: {baseline_ram:.2f} MB")
    
    # 1. Model loading
    print_separator("STEP 1: Model Initialization")
    ram_before_model = ram_mb()
    model = initialize_model(model_path)
    ram_after_model = ram_mb()
    
    model_params_mb = model_memory_mb(model)
    model_load_overhead = ram_after_model - ram_before_model
    
    print(f"\n[RESULTS - Model Loading]")
    print(f"  Model parameters & buffers: {model_params_mb:.2f} MB")
    print(f"  Total RAM increase: {model_load_overhead:.2f} MB")
    print(f"  Loading overhead: {model_load_overhead - model_params_mb:.2f} MB")
    
    # 2. Input preparation
    print_separator("STEP 2: Input Tensor Preparation")
    ram_before_input = ram_mb()
    input_tensor = prepare_input_tensor()
    ram_after_input = ram_mb()
    
    input_size_mb = input_tensor.element_size() * input_tensor.nelement() / 1024**2
    input_overhead = ram_after_input - ram_before_input
    
    print(f"\n[RESULTS - Input Preparation]")
    print(f"  Input tensor size: {input_size_mb:.4f} MB")
    print(f"  RAM increase: {input_overhead:.2f} MB")
    
    # 3. Inference
    print_separator("STEP 3: Inference Execution")
    ram_before_inference = ram_mb()
    output = run_inference(model, input_tensor)
    ram_after_inference = ram_mb()
    
    output_size_mb = output.element_size() * output.nelement() / 1024**2
    inference_overhead = ram_after_inference - ram_before_inference
    
    print(f"\n[RESULTS - Inference]")
    print(f"  Output tensor size: {output_size_mb:.6f} MB")
    print(f"  RAM increase: {inference_overhead:.2f} MB")
    # print(f"  Inference overhead: {inference_overhead - output_size_mb:.2f} MB")
    
    # Multiple inferences to check consistency
    print_separator("STEP 4: Multiple Inferences (Warm-up Test)")
    print("Running 10 inferences to check memory stability...")
    
    ram_samples = []
    for i in range(10):
        with torch.inference_mode():
            _ = model(input_tensor)
        ram_samples.append(ram_mb())
    
    avg_ram = sum(ram_samples) / len(ram_samples)
    max_ram = max(ram_samples)
    min_ram = min(ram_samples)
    
    print(f"\n[RESULTS - Stability Test]")
    print(f"  Average RAM: {avg_ram:.2f} MB")
    print(f"  Peak RAM: {max_ram:.2f} MB")
    print(f"  Min RAM: {min_ram:.2f} MB")
    print(f"  Variation: {max_ram - min_ram:.2f} MB")
    
    # Final summary
    print_separator("MOBILE DEPLOYMENT REQUIREMENTS")
    
    total_current = ram_mb()
    total_overhead = total_current - baseline_ram
    
    print("\n[BREAKDOWN]")
    print(f"  - Model weights:          {model_params_mb:>8.2f} MB")
    print(f"  - Model loading overhead: {model_load_overhead - model_params_mb:>8.2f} MB")
    print(f"  - Input tensor:           {input_size_mb:>8.4f} MB")
    # print(f"  - Inference overhead:     {inference_overhead:>8.2f} MB")
    print(f"  " + "-"*40)
    print(f"  Total model requirements:  {total_overhead:>8.2f} MB")
    print(f"  Python baseline overhead:  {baseline_ram:>8.2f} MB")
    print(f"  " + "="*40)
    print(f"  TOTAL PROCESS RAM:         {total_current:>8.2f} MB")
    
    print("\n[MOBILE DEPLOYMENT ESTIMATE]")
    # Estimate for mobile: model + input + inference overhead (without Python overhead)
    mobile_estimate = model_params_mb + input_size_mb + inference_overhead
    
    print(f"  Minimum RAM needed:        {mobile_estimate:>8.2f} MB")
    print(f"  Recommended (with buffer): {mobile_estimate * 1.5:>8.2f} MB")
    
    print("\n[OPTIMIZATION NOTES]")
    print(f"  - Model file size: ~14 MB (on disk)")
    print(f"  - Model in memory: {model_params_mb:.2f} MB (in RAM)")
    print(f"  - Python overhead: {baseline_ram:.2f} MB (not needed for mobile)")
    print(f"  - For mobile: Use quantization or ONNX to reduce further")
    
    print("\n" + "="*70)
    print("Profile complete! Check detailed line-by-line output above.")
    print("="*70 + "\n")


if __name__ == '__main__':
    main()
