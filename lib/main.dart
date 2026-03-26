import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter_pytorch_lite/flutter_pytorch_lite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const FaceLivenessApp());
}

class FaceLivenessApp extends StatelessWidget {
  const FaceLivenessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Liveness',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1a1a2e),
      ),
      home: const LivenessDetectionPage(),
    );
  }
}

class LivenessDetectionPage extends StatefulWidget {
  const LivenessDetectionPage({super.key});

  @override
  State<LivenessDetectionPage> createState() => _LivenessDetectionPageState();
}

class _LivenessDetectionPageState extends State<LivenessDetectionPage> {
  CameraController? _cameraController;
  Module? _module;
  bool _isModelLoaded = false;
  bool _isCameraReady = false;
  bool _isProcessing = false;

  String _result = "Initializing...";
  double _confidence = 0.0;
  bool _isReal = false;

  Timer? _inferenceTimer;

  // ImageNet normalization values
  static const List<double> mean = [0.485, 0.456, 0.406];
  static const List<double> std = [0.229, 0.224, 0.225];

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadModel();
    await _initializeCamera();
    _startInferenceLoop();
  }

  Future<Uint8List> _getAssetBuffer(String assetFileName) async {
    ByteData rawAssetFile = await rootBundle.load(assetFileName);
    return rawAssetFile.buffer.asUint8List();
  }

  Future<void> _loadModel() async {
    try {
      // Copy model from assets to temp directory
      final filePath = '${Directory.systemTemp.path}/mobilenetv2_mobile.ptl';
      final modelFile = File(filePath);

      if (!await modelFile.exists()) {
        final bytes = await _getAssetBuffer('assets/mobilenetv2_mobile.ptl');
        await modelFile.writeAsBytes(bytes);
      }

      // Load the model
      _module = await FlutterPytorchLite.load(filePath);

      setState(() {
        _isModelLoaded = true;
        _result = "Model loaded";
      });
    } catch (e) {
      setState(() {
        _result = "Model error: $e";
      });
      debugPrint("Model loading error: $e");
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _result = "No camera found");
        return;
      }

      // Prefer front camera
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraReady = true;
          _result = "Ready";
        });
      }
    } catch (e) {
      setState(() => _result = "Camera error: $e");
    }
  }

  void _startInferenceLoop() {
    // Run inference every 500ms
    _inferenceTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _runInference();
    });
  }

  Future<void> _runInference() async {
    if (!_isModelLoaded || !_isCameraReady || _isProcessing) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_module == null) return;

    _isProcessing = true;

    try {
      // Capture image
      final XFile imageFile = await _cameraController!.takePicture();

      // Load image using TensorImageUtils
      final imageProvider = FileImage(File(imageFile.path));
      final image = await TensorImageUtils.imageProviderToImage(imageProvider);

      // Convert to tensor (NCHW format: batch=1, channels=3, height=224, width=224)
      final inputShape = Int64List.fromList([1, 3, 224, 224]);
      Tensor inputTensor = await TensorImageUtils.imageToFloat32Tensor(
        image,
        width: 224,
        height: 224,
        mean: mean,
        std: std,
      );

      // Run forward pass
      IValue input = IValue.from(inputTensor);
      IValue output = await _module!.forward([input]);

      // Get output tensor
      Tensor outputTensor = output.toTensor();
      Float32List outputData = outputTensor.dataAsFloat32List;

      // Our model outputs a single sigmoid value: probability of being real
      double probReal = 0.5;
      if (outputData.isNotEmpty) {
        probReal = outputData[0];
        probReal = probReal.clamp(0.0, 1.0);
      }

      // Determine result
      final bool isReal = probReal > 0.5;
      final double confidence = isReal ? probReal : (1 - probReal);

      // Clean up captured image
      await File(imageFile.path).delete();

      if (mounted) {
        setState(() {
          _isReal = isReal;
          _confidence = confidence;
          _result = isReal ? "REAL" : "SPOOF";
        });
      }
    } catch (e) {
      debugPrint("Inference error: $e");
    } finally {
      _isProcessing = false;
    }
  }

  @override
  void dispose() {
    _inferenceTimer?.cancel();
    _cameraController?.dispose();
    _module?.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                "Face Liveness Detection",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ),

            // Camera preview
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isCameraReady
                        ? (_isReal ? Colors.green : Colors.red)
                        : Colors.grey,
                    width: 4,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _isCameraReady && _cameraController != null
                    ? CameraPreview(_cameraController!)
                    : const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text("Initializing camera..."),
                          ],
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 16),

            // Result display
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: _isReal
                    ? Colors.green.withOpacity(0.2)
                    : Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _isReal ? Colors.green : Colors.red,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isReal ? Icons.check_circle : Icons.warning,
                        color: _isReal ? Colors.green : Colors.red,
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _result,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: _isReal ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Confidence: ${(_confidence * 100).toStringAsFixed(1)}%",
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Status indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStatusChip("Model", _isModelLoaded),
                      const SizedBox(width: 8),
                      _buildStatusChip("Camera", _isCameraReady),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? Icons.check : Icons.hourglass_empty,
            size: 14,
            color: isActive ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isActive ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
