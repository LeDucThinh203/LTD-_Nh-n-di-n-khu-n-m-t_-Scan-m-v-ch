import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({Key? key}) : super(key: key);

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  CameraController? _cameraController;
  late final BarcodeScanner _barcodeScanner;
  bool _isBusy = false;
  String? _barcodeResult;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.all]);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _barcodeScanner.close();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final camera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
    );

    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    await _cameraController!.startImageStream(_processCameraImage);

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isBusy) return;
    _isBusy = true;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(
        image.width.toDouble(),
        image.height.toDouble(),
      );

      final camera = _cameraController!.description;
      final rotation = InputImageRotationValue.fromRawValue(
          camera.sensorOrientation) ??
          InputImageRotation.rotation0deg;

      final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21;

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      final barcodes = await _barcodeScanner.processImage(inputImage);

      if (barcodes.isNotEmpty) {
        setState(() {
          _barcodeResult = barcodes.first.rawValue ?? 'Không đọc được';
        });
      }
    } catch (e) {
      debugPrint("Lỗi xử lý ảnh: $e");
    }

    _isBusy = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Quét mã vạch (ML Kit)")),
      body: _cameraController == null || !_cameraController!.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          CameraPreview(_cameraController!),
          if (_barcodeResult != null)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                color: Colors.black54,
                child: Text(
                  'Kết quả: $_barcodeResult',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
