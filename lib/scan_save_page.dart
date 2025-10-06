import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

import 'face_painter.dart';

class ScanSavePage extends StatefulWidget {
  const ScanSavePage({super.key});

  @override
  State<ScanSavePage> createState() => _ScanSavePageState();
}

class _ScanSavePageState extends State<ScanSavePage> {
  CameraController? _cameraController;
  late FaceDetector _faceDetector;
  List<Face> _faces = [];
  bool _isDetecting = false;
  bool _showDebug = false; // toggle để xem log / debug

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initFaceDetector();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final camera = cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _cameraController!.initialize();
    await _cameraController!.startImageStream(_processCameraImage);
    if (mounted) setState(() {});
  }

  void _initFaceDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableClassification: true, // cần cho smilingProbability
        enableTracking: true,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.08, // thử giảm để dễ bắt khi xa
      ),
    );
  }

  InputImageRotation _rotationFromSensor() {
    if (_cameraController == null) return InputImageRotation.rotation0deg;
    final rotation = _cameraController!.description.sensorOrientation;
    switch (rotation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting) return;
    _isDetecting = true;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final InputImageRotation rotation = _rotationFromSensor();

      // Format suy đoán: yuv420
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.yuv420,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      final faces = await _faceDetector.processImage(inputImage);
      if (_showDebug) {
        for (var f in faces) {
          debugPrint(
            'Face => smile=${f.smilingProbability?.toStringAsFixed(3)} bb=${f.boundingBox} tracking=${f.trackingId}',
          );
        }
      }
      if (mounted) setState(() => _faces = faces);
    } catch (e) {
      debugPrint('Lỗi xử lý ảnh: $e');
    }

    _isDetecting = false;
  }

  Future<void> _scanAndSaveFaces() async {
    String? personName = await _askForName();
    if (personName == null || personName.isEmpty) return;

    final dir = await getApplicationDocumentsDirectory();
    final personDir = Directory('${dir.path}/faces/$personName');
    if (!personDir.existsSync()) personDir.createSync(recursive: true);

    for (int i = 0; i < 10; i++) {
      try {
        final image = await _cameraController!.takePicture();
        final filePath =
            '${personDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await image.saveTo(filePath);
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint("Lỗi khi chụp ảnh: $e");
        i--; // thử lại
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Quét thành công! 10 ảnh đã được lưu")),
      );
    }
  }

  Future<String?> _askForName() async {
    String name = "";
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Nhập tên người"),
        content: TextField(
          autofocus: true,
          onChanged: (value) => name = value,
          decoration: const InputDecoration(hintText: "Tên..."),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text("Hủy"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, name),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("📸 Scan & Lưu")),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraController!),
          CustomPaint(
            painter: FacePainter(
              _faces,
              _cameraController!.value.previewSize!,
              isFront:
                  _cameraController!.description.lensDirection ==
                  CameraLensDirection.front,
              rotation: _rotationFromSensor(),
              showDebug: _showDebug,
            ),
          ),
          // Nút tròn kiểu camera
          Positioned(
            bottom: 26,
            right: 26,
            child: Column(
              children: [
                _roundBtn(
                  icon: Icons.bug_report,
                  color: _showDebug ? Colors.deepOrange : Colors.grey.shade700,
                  onTap: () => setState(() => _showDebug = !_showDebug),
                ),
                const SizedBox(height: 14),
                _roundBtn(
                  icon: Icons.camera_alt,
                  color: Colors.blueAccent,
                  onTap: _scanAndSaveFaces,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 6,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}
