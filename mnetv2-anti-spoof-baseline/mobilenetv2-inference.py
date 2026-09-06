"""
Real-time Face Anti-Spoofing Inference with MobileNetV2
Performs liveness detection on webcam feed using trained SpoofNet model
"""

import argparse
import cv2
import torch
import torch.nn as nn
import numpy as np
from PIL import Image
import torchvision.transforms as transforms
from torchvision.models import mobilenet_v2
import os
import sys
import time
import psutil


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


def parse_args():
    parser = argparse.ArgumentParser(description='Face Anti-Spoofing Inference - MobileNetV2')
    parser.add_argument('--model_path', type=str, default='mobilenetv2-best.pt',
                        help='Path to trained model checkpoint (.pt file)')
    parser.add_argument('--threshold', type=float, default=0.5,
                        help='Classification threshold (default: 0.5)')
    parser.add_argument('--camera_id', type=int, default=0,
                        help='Camera device ID (default: 0)')
    parser.add_argument('--display_size', type=int, default=480,
                        help='Display window size (default: 480, reduced for lower memory)')
    return parser.parse_args()


def model_memory_mb(model):
    """
    Calculate total memory used by model parameters and buffers
    
    Args:
        model: PyTorch model
    
    Returns:
        float: Memory usage in MB
    """
    param_mem = sum(p.numel() * p.element_size() for p in model.parameters())
    buffer_mem = sum(b.numel() * b.element_size() for b in model.buffers())
    return (param_mem + buffer_mem) / 1024**2


def ram_mb():
    """
    Get current process RAM usage in MB
    
    Returns:
        float: RAM usage in MB
    """
    process = psutil.Process(os.getpid())
    return process.memory_info().rss / 1024**2


def get_python_baseline_ram():
    """
    Get Python interpreter baseline RAM (before model loading)
    
    Returns:
        float: Baseline RAM usage in MB
    """
    return ram_mb()


def get_inference_ram_usage(current_ram, baseline_ram):
    """
    Calculate actual inference/model RAM usage (excluding Python overhead)
    
    Args:
        current_ram: Current process RAM in MB
        baseline_ram: Python baseline RAM in MB
    
    Returns:
        float: Inference RAM usage in MB
    """
    return current_ram - baseline_ram


def load_model(model_path, device='cpu'):
    """
    Load the trained SpoofNet model from checkpoint
    """
    try:
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Model file not found: {model_path}")
        
        print(f"Loading model from: {model_path}")
        
        # Initialize model architecture
        model = SpoofNet()
        
        # Load checkpoint
        checkpoint = torch.load(model_path, map_location=device)
        
        # Extract state dict from checkpoint
        if isinstance(checkpoint, dict) and 'state_dict' in checkpoint:
            model.load_state_dict(checkpoint['state_dict'])
            epoch = checkpoint.get('epoch', 'unknown')
            print(f"Loaded checkpoint from epoch: {epoch}")
        else:
            # If checkpoint is just the state dict
            model.load_state_dict(checkpoint)
        
        model.eval()
        model.to(device)
        
        print("Model loaded successfully!")
        print(f"Model memory: {model_memory_mb(model):.2f} MB")
        return model
    
    except Exception as e:
        print(f"Error loading model: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


def get_transform():
    """
    Define image transformations matching training pipeline
    """
    return transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], 
                           std=[0.229, 0.224, 0.225])
    ])


def preprocess_frame(frame, transform):
    """
    Preprocess video frame for model input
    
    Args:
        frame: BGR image from OpenCV
        transform: torchvision transforms
    
    Returns:
        Preprocessed tensor ready for model
    """
    try:
        # Convert BGR to RGB
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        
        # Convert to PIL Image
        pil_image = Image.fromarray(frame_rgb)
        
        # Apply transforms
        tensor = transform(pil_image)
        
        # Add batch dimension
        tensor = tensor.unsqueeze(0)
        
        return tensor
    
    except Exception as e:
        print(f"Error preprocessing frame: {e}")
        return None


def predict(model, frame_tensor, device, threshold=0.5, verbose=False):
    """
    Make prediction on preprocessed frame
    
    Args:
        model: Loaded SpoofNet model
        frame_tensor: Preprocessed frame tensor
        device: torch device
        threshold: Classification threshold
        verbose: Print RAM usage before/after inference
    
    Returns:
        is_real (bool): True if real face, False if spoof
        confidence (float): Confidence score [0-1]
        probabilities (tuple): (prob_spoof, prob_real)
    """
    try:
        if verbose:
            ram_before = ram_mb()
            print(f"RAM before inference: {ram_before:.2f} MB")
        
        with torch.inference_mode():
            frame_tensor = frame_tensor.to(device)
            
            # Forward pass - returns sigmoid output [0-1]
            output = model(frame_tensor)
            
            # Get probability of being real (model outputs probability of class 1)
            prob_real = output[0, 0].item()
            prob_spoof = 1.0 - prob_real
            
            # Determine prediction
            is_real = prob_real > threshold
            confidence = prob_real if is_real else prob_spoof
        
        if verbose:
            ram_after = ram_mb()
            print(f"RAM after inference: {ram_after:.2f} MB")
            print(f"RAM used by inference: {ram_after - ram_before:.2f} MB")
            
        return is_real, confidence, (prob_spoof, prob_real)
    
    except Exception as e:
        print(f"Error during prediction: {e}")
        import traceback
        traceback.print_exc()
        return None, 0.0, (0.0, 0.0)


def get_resource_usage(baseline_ram):
    """
    Get current RAM and CPU usage using psutil
    
    Args:
        baseline_ram: Python baseline RAM in MB
    
    Returns:
        dict: Contains inference RAM (MB), CPU (%), and process info
    """
    try:
        process = psutil.Process(os.getpid())
        memory_info = process.memory_info()
        total_memory_mb = memory_info.rss / 1024 / 1024  # Convert bytes to MB
        inference_memory_mb = total_memory_mb - baseline_ram  # Subtract Python overhead
        cpu_percent = process.cpu_percent(interval=0.1)
        
        # Get system-wide memory
        virtual_memory = psutil.virtual_memory()
        system_memory_percent = virtual_memory.percent
        
        return {
            'total_memory_mb': total_memory_mb,
            'inference_memory_mb': inference_memory_mb,
            'process_cpu_percent': cpu_percent,
            'system_memory_percent': system_memory_percent,
        }
    except Exception as e:
        print(f"Error getting resource usage: {e}")
        return None


def print_resource_stats(frame_count, baseline_ram):
    """
    Print resource usage statistics (inference RAM only)
    
    Args:
        frame_count: Current frame count
        baseline_ram: Python baseline RAM in MB
    """
    resources = get_resource_usage(baseline_ram)
    if resources:
        print(
            f"[Frame {frame_count}] | "
            f"Inference RAM: {resources['inference_memory_mb']:.1f} MB | "
            f"Total: {resources['total_memory_mb']:.1f} MB | "
            f"CPU: {resources['process_cpu_percent']:.1f}% | "
            f"System RAM: {resources['system_memory_percent']:.1f}%"
        )


def draw_results(frame, is_real, confidence, prob_spoof, prob_real):
    """
    Draw prediction results on frame
    
    Args:
        frame: Original frame
        is_real: Boolean indicating if face is real
        confidence: Confidence score
        prob_spoof: Spoof probability
        prob_real: Real probability
    
    Returns:
        Frame with annotations
    """
    height, width = frame.shape[:2]
    
    # Determine color and label
    if is_real:
        color = (0, 255, 0)  # Green for real
        label = "REAL FACE"
    else:
        color = (0, 0, 255)  # Red for spoof
        label = "SPOOF DETECTED"
    
    # Draw background rectangle for text
    overlay = frame.copy()
    cv2.rectangle(overlay, (10, 10), (width - 10, 120), (0, 0, 0), -1)
    cv2.addWeighted(overlay, 0.6, frame, 0.4, 0, frame)
    
    # Draw main prediction label
    cv2.putText(frame, label, (20, 50), 
                cv2.FONT_HERSHEY_SIMPLEX, 1.2, color, 3)
    
    # Draw confidence
    conf_text = f"Confidence: {confidence:.2%}"
    cv2.putText(frame, conf_text, (20, 85), 
                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
    
    # Draw probabilities
    prob_text = f"Real: {prob_real:.2%} | Spoof: {prob_spoof:.2%}"
    cv2.putText(frame, prob_text, (20, 110), 
                cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
    
    # Draw border
    border_thickness = 5
    cv2.rectangle(frame, (0, 0), (width - 1, height - 1), color, border_thickness)
    
    return frame


def main():
    args = parse_args()
    
    # Get Python baseline RAM before loading anything
    baseline_ram = get_python_baseline_ram()
    print(f"Python baseline RAM: {baseline_ram:.2f} MB")
    
    # Set device to CPU (change to 'cuda' if GPU available)
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"Using device: {device}")
    
    # Load model
    model = load_model(args.model_path, device)
    
    # Get transform
    transform = get_transform()
    
    # Initialize camera
    print(f"Opening camera {args.camera_id}...")
    ram_before_camera = ram_mb()
    inference_ram_before = get_inference_ram_usage(ram_before_camera, baseline_ram)
    print(f"Inference RAM before opening camera: {inference_ram_before:.2f} MB")
    
    cap = cv2.VideoCapture(args.camera_id)
    
    if not cap.isOpened():
        print(f"Error: Could not open camera {args.camera_id}")
        print("Please check:")
        print("1. Camera is connected")
        print("2. Camera permissions are granted")
        print("3. Camera is not being used by another application")
        sys.exit(1)
    
    # Set camera properties to lower resolution for reduced memory footprint
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 320)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 240)
    
    ram_after_camera = ram_mb()
    inference_ram_after = get_inference_ram_usage(ram_after_camera, baseline_ram)
    print(f"Inference RAM after opening camera: {inference_ram_after:.2f} MB")
    print(f"Camera inference RAM usage: {inference_ram_after - inference_ram_before:.2f} MB")
    
    print("\n" + "="*70)
    print("Face Anti-Spoofing System - MobileNetV2")
    print("="*70)
    print(f"Model: {args.model_path}")
    print(f"Threshold: {args.threshold}")
    print(f"Device: {device}")
    print(f"Camera Resolution: 320x240 (optimized for low memory)")
    print(f"Display Size: {args.display_size}px")
    print(f"\nMemory Usage:  ")
    print(f"  Python baseline: {baseline_ram:.2f} MB")
    print(f"  Current inference RAM: {get_inference_ram_usage(ram_mb(), baseline_ram):.2f} MB")
    print("\nControls:")
    print("  'q' or 'ESC' - Quit")
    print("  's' - Save current frame")
    print("  'v' - Toggle verbose RAM tracking")
    print("="*70 + "\n")
    
    frame_count = 0
    saved_count = 0
    last_stats_time = time.time()
    stats_interval = 5.0  # Print stats every 5 seconds
    verbose_ram = False  # Toggle verbose RAM tracking
    
    try:
        while True:
            # Read frame
            ret, frame = cap.read()
            
            if not ret:
                print("Error: Failed to read frame from camera")
                break
            
            frame_count += 1
            
            # Print resource stats every 5 seconds
            current_time = time.time()
            if current_time - last_stats_time >= stats_interval:
                print_resource_stats(frame_count, baseline_ram)
                last_stats_time = current_time
            
            # Resize frame for display
            display_frame = cv2.resize(frame, (args.display_size, 
                                              int(args.display_size * frame.shape[0] / frame.shape[1])))
            
            # Preprocess frame
            frame_tensor = preprocess_frame(frame, transform)
            
            if frame_tensor is not None:
                # Make prediction
                is_real, confidence, (prob_spoof, prob_real) = predict(
                    model, frame_tensor, device, args.threshold, verbose=verbose_ram
                )
                
                # Draw results
                if is_real is not None:
                    display_frame = draw_results(
                        display_frame, is_real, confidence, prob_spoof, prob_real
                    )
            else:
                # Draw error message
                cv2.putText(display_frame, "Processing Error", (20, 50),
                           cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 2)
            
            # Display frame
            cv2.imshow('Face Anti-Spoofing Detection - MobileNetV2', display_frame)
            
            # Handle key presses
            key = cv2.waitKey(1) & 0xFF
            
            if key == ord('q') or key == 27:  # 'q' or ESC
                print("\nShutting down...")
                break
            elif key == ord('s'):  # Save frame
                saved_count += 1
                filename = f"capture_{saved_count}.jpg"
                cv2.imwrite(filename, display_frame)
                print(f"Saved: {filename}")
            elif key == ord('v'):  # Toggle verbose RAM tracking
                verbose_ram = not verbose_ram
                status = "ENABLED" if verbose_ram else "DISABLED"
                print(f"\nVerbose RAM tracking: {status}")
    
    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
    
    except Exception as e:
        print(f"\nUnexpected error: {e}")
        import traceback
        traceback.print_exc()
    
    finally:
        # Cleanup
        print("\nCleaning up...")
        cap.release()
        cv2.destroyAllWindows()
        print(f"Total frames processed: {frame_count}")
        print("Done!")


if __name__ == '__main__':
    main()
