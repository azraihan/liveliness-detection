# Android Face Anti-Spoofing App Guide

## Overview
This guide walks you through deploying the MobileNetV2 face anti-spoofing model (`mobilenetv2-best.pt`) in a simple Android application that performs real-time classification.

---

## Part 1: Model Preparation

### Step 1: Convert PyTorch Model to TorchScript Mobile Format

PyTorch models need to be converted to TorchScript format for mobile deployment.

```python
import torch
import torch.nn as nn
from torchvision import models

# Load your trained model
model = models.mobilenet_v2(pretrained=False)
# Modify final layer to match your training (2 classes: Real/Spoof)
model.classifier[1] = nn.Linear(model.last_channel, 2)

# Load trained weights
checkpoint = torch.load('mobilenetv2-best.pt')
model.load_state_dict(checkpoint['model_state_dict'] if 'model_state_dict' in checkpoint else checkpoint)
model.eval()

# Convert to TorchScript
example_input = torch.rand(1, 3, 224, 224)  # Adjust size to match your training
traced_script_module = torch.jit.trace(model, example_input)

# Optimize for mobile
traced_script_module_optimized = torch.utils.mobile_optimizer.optimize_for_mobile(traced_script_module)

# Save the mobile-optimized model
traced_script_module_optimized._save_for_lite_interpreter("mobilenetv2_mobile.ptl")
```

**Key Points:**
- Input size must match your training configuration (commonly 224x224 for MobileNetV2)
- The `.ptl` format is optimized for mobile devices
- Test the conversion locally before moving to Android

---

## Part 2: Android Application Development

### Step 2: Set Up Android Project

1. **Create New Android Project**
   - Open Android Studio
   - Create new project: "Empty Activity"
   - Language: Kotlin (recommended) or Java
   - Minimum SDK: API 24 (Android 7.0) or higher

2. **Add PyTorch Mobile Dependencies**

In `app/build.gradle`:

```gradle
dependencies {
    implementation 'org.pytorch:pytorch_android:1.13.1'
    implementation 'org.pytorch:pytorch_android_torchvision:1.13.1'

    // CameraX dependencies
    def camerax_version = "1.2.3"
    implementation "androidx.camera:camera-core:${camerax_version}"
    implementation "androidx.camera:camera-camera2:${camerax_version}"
    implementation "androidx.camera:camera-lifecycle:${camerax_version}"
    implementation "androidx.camera:camera-view:${camerax_version}"
}
```

3. **Add Model to Assets**
   - Create `app/src/main/assets` folder if it doesn't exist
   - Copy `mobilenetv2_mobile.ptl` to this folder
   - Configure gradle to not compress the model:

```gradle
android {
    aaptOptions {
        noCompress "ptl"
    }
}
```

### Step 3: Add Permissions

In `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera" android:required="true" />
```

### Step 4: Create Simple UI Layout

`activity_main.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <androidx.camera.view.PreviewView
        android:id="@+id/previewView"
        android:layout_width="0dp"
        android:layout_height="0dp"
        app:layout_constraintTop_toTopOf="parent"
        app:layout_constraintBottom_toTopOf="@id/resultContainer"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent" />

    <LinearLayout
        android:id="@+id/resultContainer"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:padding="16dp"
        android:background="#F0F0F0"
        app:layout_constraintBottom_toBottomOf="parent">

        <TextView
            android:id="@+id/resultText"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="Result: -"
            android:textSize="24sp"
            android:textStyle="bold" />

        <TextView
            android:id="@+id/confidenceText"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="Confidence: -"
            android:textSize="18sp"
            android:layout_marginTop="8dp" />
    </LinearLayout>

</androidx.constraintlayout.widget.ConstraintLayout>
```

### Step 5: Implement Main Activity (Kotlin)

`MainActivity.kt`:

```kotlin
import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.os.Bundle
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import org.pytorch.IValue
import org.pytorch.Module
import org.pytorch.torchvision.TensorImageUtils
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : AppCompatActivity() {

    private lateinit var previewView: PreviewView
    private lateinit var resultText: TextView
    private lateinit var confidenceText: TextView
    private lateinit var cameraExecutor: ExecutorService
    private var module: Module? = null

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        if (isGranted) {
            startCamera()
        } else {
            Toast.makeText(this, "Camera permission required", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        previewView = findViewById(R.id.previewView)
        resultText = findViewById(R.id.resultText)
        confidenceText = findViewById(R.id.confidenceText)

        cameraExecutor = Executors.newSingleThreadExecutor()

        // Load PyTorch model
        try {
            module = Module.load(assetFilePath("mobilenetv2_mobile.ptl"))
            Toast.makeText(this, "Model loaded successfully", Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            Toast.makeText(this, "Error loading model: ${e.message}", Toast.LENGTH_LONG).show()
            e.printStackTrace()
        }

        // Request camera permission
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED) {
            startCamera()
        } else {
            requestPermissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)

        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()

            val preview = Preview.Builder().build().also {
                it.setSurfaceProvider(previewView.surfaceProvider)
            }

            val imageAnalyzer = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also {
                    it.setAnalyzer(cameraExecutor, FaceAnalyzer())
                }

            val cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA

            try {
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(
                    this, cameraSelector, preview, imageAnalyzer
                )
            } catch (e: Exception) {
                Toast.makeText(this, "Camera binding failed: ${e.message}",
                    Toast.LENGTH_SHORT).show()
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private inner class FaceAnalyzer : ImageAnalysis.Analyzer {
        private var lastAnalyzedTimestamp = 0L

        override fun analyze(imageProxy: ImageProxy) {
            val currentTimestamp = System.currentTimeMillis()
            // Process every 500ms to avoid overload
            if (currentTimestamp - lastAnalyzedTimestamp >= 500) {
                val bitmap = imageProxy.toBitmap()
                bitmap?.let { processImage(it) }
                lastAnalyzedTimestamp = currentTimestamp
            }
            imageProxy.close()
        }
    }

    private fun processImage(bitmap: Bitmap) {
        module?.let { model ->
            try {
                // Resize bitmap to model input size (224x224)
                val resizedBitmap = Bitmap.createScaledBitmap(bitmap, 224, 224, true)

                // Convert to tensor with normalization
                // Adjust normalization values based on your training
                val inputTensor = TensorImageUtils.bitmapToFloat32Tensor(
                    resizedBitmap,
                    floatArrayOf(0.485f, 0.456f, 0.406f), // mean
                    floatArrayOf(0.229f, 0.224f, 0.225f)  // std
                )

                // Run inference
                val outputTensor = model.forward(IValue.from(inputTensor)).toTensor()
                val scores = outputTensor.dataAsFloatArray

                // Apply softmax to get probabilities
                val expScores = scores.map { kotlin.math.exp(it.toDouble()) }
                val sumExp = expScores.sum()
                val probabilities = expScores.map { (it / sumExp).toFloat() }

                // Get prediction
                val maxIndex = probabilities.indices.maxByOrNull { probabilities[it] } ?: 0
                val confidence = probabilities[maxIndex]
                val prediction = if (maxIndex == 0) "REAL" else "SPOOF"

                // Update UI
                runOnUiThread {
                    resultText.text = "Result: $prediction"
                    confidenceText.text = "Confidence: ${String.format("%.2f", confidence * 100)}%"

                    // Color code the result
                    val color = if (prediction == "REAL")
                        android.graphics.Color.GREEN else android.graphics.Color.RED
                    resultText.setTextColor(color)
                }

            } catch (e: Exception) {
                runOnUiThread {
                    resultText.text = "Error: ${e.message}"
                }
                e.printStackTrace()
            }
        }
    }

    private fun assetFilePath(assetName: String): String {
        val file = java.io.File(filesDir, assetName)
        if (file.exists() && file.length() > 0) {
            return file.absolutePath
        }

        assets.open(assetName).use { inputStream ->
            java.io.FileOutputStream(file).use { outputStream ->
                val buffer = ByteArray(4 * 1024)
                var read: Int
                while (inputStream.read(buffer).also { read = it } != -1) {
                    outputStream.write(buffer, 0, read)
                }
                outputStream.flush()
            }
        }
        return file.absolutePath
    }

    override fun onDestroy() {
        super.onDestroy()
        cameraExecutor.shutdown()
    }
}

// Extension function to convert ImageProxy to Bitmap
fun ImageProxy.toBitmap(): Bitmap? {
    val buffer = planes[0].buffer
    val bytes = ByteArray(buffer.remaining())
    buffer.get(bytes)
    return android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
}
```

---

## Part 3: Key Points for End-to-End Flow

### Model Inference Pipeline

1. **Image Capture** → CameraX captures frames at 30+ fps
2. **Preprocessing** → Resize to 224x224 and normalize with ImageNet stats
3. **Inference** → PyTorch Mobile runs model on preprocessed tensor
4. **Postprocessing** → Apply softmax to get probabilities
5. **Display** → Show classification result and confidence on UI

### Important Configuration Details

- **Input Normalization**: Must match training (typically ImageNet: mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
- **Input Size**: 224x224 for MobileNetV2
- **Output Classes**: Index 0 = Real, Index 1 = Spoof (verify with your training)
- **Inference Frequency**: Throttle to every 500ms to prevent UI lag and battery drain

---

## Part 4: Critical Pitfalls & Considerations

### 1. **Model Size and Performance**
- **Issue**: MobileNetV2 is designed for mobile but still consumes resources
- **Solution**:
  - Use `.ptl` format (optimized for mobile)
  - Throttle inference frequency (process every 500ms, not every frame)
  - Consider quantization for even smaller model size

### 2. **Preprocessing Discrepancy**
- **Issue**: Most common cause of poor accuracy - normalization mismatch between training and inference
- **Solution**:
  - Double-check mean/std values match your training code exactly
  - Verify color channel order (RGB vs BGR)
  - Test the converted model with known images before deploying

### 3. **Camera Orientation and Mirroring**
- **Issue**: Front camera images are often mirrored and rotated
- **Solution**:
  - Test with both front and back cameras
  - Add image transformation if needed
  - Consider training with augmented data including flips

### 4. **Memory Management**
- **Issue**: Processing high-resolution images can cause OOM errors
- **Solution**:
  - Always resize images before inference
  - Reuse bitmap objects where possible
  - Close ImageProxy after processing
  - Monitor memory usage in Android Profiler

### 5. **Model Loading Time**
- **Issue**: Loading model on app start can freeze UI
- **Solution**:
  - Load model asynchronously (in code above, it's synchronous for simplicity)
  - Show loading indicator
  - Cache model in memory once loaded

### 6. **Thread Safety**
- **Issue**: PyTorch module is not thread-safe
- **Solution**:
  - Run inference on a single background thread (ExecutorService with single thread)
  - Never call model from multiple threads simultaneously

### 7. **Real-time Performance**
- **Issue**: Inference might be slower than expected on low-end devices
- **Solution**:
  - Test on various devices (not just your development phone)
  - Profile with Android Profiler
  - Consider using NNAPI delegate for hardware acceleration:
    ```kotlin
    module = Module.load(assetFilePath("mobilenetv2_mobile.ptl"), null, Device.GPU)
    ```

### 8. **Class Index Confusion**
- **Issue**: Mismatch between training labels and inference output
- **Solution**:
  - Verify which output index corresponds to "Real" vs "Spoof"
  - Add logging during testing phase
  - Consider saving class names in the model or config file

### 9. **Lighting and Quality**
- **Issue**: Poor camera quality or lighting reduces accuracy
- **Solution**:
  - Add minimum brightness check
  - Provide user feedback (e.g., "Move to better lighting")
  - Consider face detection to ensure face is present and properly framed

### 10. **Battery Drain**
- **Issue**: Continuous camera + inference drains battery quickly
- **Solution**:
  - Implement auto-pause when app is in background
  - Add manual capture mode as alternative to continuous inference
  - Use lower camera resolution for preview

### 11. **APK Size**
- **Issue**: PyTorch library adds ~20MB to APK
- **Solution**:
  - Use Android App Bundle for dynamic delivery
  - Enable ProGuard/R8 for code shrinking
  - Consider model quantization to reduce model size

### 12. **Testing Strategy**
- Test model conversion with known images before Android integration
- Verify softmax probabilities sum to 1.0
- Test with both real faces and spoofing attempts
- Profile performance on low-end devices (not just flagship phones)
- Test edge cases: poor lighting, partial faces, multiple faces

---

## Part 5: Testing Checklist

Before deploying:

- [ ] Model loads successfully without errors
- [ ] Inference produces sensible results (not random predictions)
- [ ] FPS is acceptable (at least 1-2 inferences per second)
- [ ] App doesn't crash on low-memory devices
- [ ] Battery consumption is reasonable
- [ ] Permissions are handled properly
- [ ] App works on devices with different screen sizes
- [ ] Results match expected behavior from training

---

## Quick Troubleshooting

| Problem | Solution |
|---------|----------|
| Model won't load | Check `.ptl` file is in assets, verify gradle configuration |
| Random predictions | Verify preprocessing normalization matches training |
| Crashes after few seconds | Memory leak - ensure ImageProxy.close() is called |
| Very slow inference | Throttle to lower frequency, check device performance |
| Black screen | Camera permission not granted or camera binding failed |
| Inverted predictions | Check class index mapping (swap Real/Spoof) |

---

## Next Steps

1. Convert your model using the Python script
2. Set up Android project and add dependencies
3. Test model loading in isolation first
4. Add camera functionality
5. Integrate inference pipeline
6. Test thoroughly on multiple devices
7. Optimize based on profiling results

Good luck with your face anti-spoofing app! 🚀
