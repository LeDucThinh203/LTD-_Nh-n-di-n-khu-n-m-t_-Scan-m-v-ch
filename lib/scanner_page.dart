import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({Key? key}) : super(key: key);

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  late final BarcodeScanner _barcodeScanner;
  bool _isBusy = false;
  String? _barcodeResult;
  BarcodeFormat? _barcodeFormat;
  bool _streamStopped = false;
  bool _isFlashOn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    // Sửa lỗi chính: BarcodeFormat.all không thể dùng trong list
    _barcodeScanner = BarcodeScanner(
      formats: [
        BarcodeFormat.qrCode,
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.upca,
        BarcodeFormat.upce,
        BarcodeFormat.code93,
        BarcodeFormat.codabar,
        BarcodeFormat.itf,
        BarcodeFormat.aztec,
        BarcodeFormat.dataMatrix,
        BarcodeFormat.pdf417,
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _barcodeScanner.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      // Kiểm tra camera permission
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('Không tìm thấy camera');
      }

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      // Kiểm tra camera đã khởi tạo thành công
      if (!_cameraController!.value.isInitialized) {
        throw Exception('Camera không khởi tạo được');
      }

      await _cameraController!.setFocusMode(FocusMode.auto);
      await _cameraController!.setExposureMode(ExposureMode.auto);

      await _cameraController!.startImageStream(_processCameraImage);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Lỗi khởi tạo camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Lỗi camera: $e\nVui lòng cấp quyền camera trong Settings',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // Thêm throttle để giảm tần suất xử lý
  DateTime? _lastProcessTime;
  static const Duration _processingInterval = Duration(
    milliseconds: 100,
  ); // 10 FPS

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isBusy || _streamStopped) return;

    // Throttle processing
    final now = DateTime.now();
    if (_lastProcessTime != null &&
        now.difference(_lastProcessTime!) < _processingInterval) {
      return;
    }
    _lastProcessTime = now;

    _isBusy = true;

    try {
      final inputImage = _convertCameraImage(image);

      if (inputImage != null) {
        final barcodes = await _barcodeScanner.processImage(inputImage);

        if (barcodes.isNotEmpty) {
          debugPrint('Found ${barcodes.length} barcodes');
          for (var barcode in barcodes) {
            debugPrint('Barcode format: ${barcode.format}');
            debugPrint('Barcode value: ${barcode.rawValue}');
            debugPrint('Barcode bounds: ${barcode.boundingBox}');
          }
        }

        if (barcodes.isNotEmpty && mounted) {
          final barcode = barcodes.first;
          final value = barcode.rawValue ?? '';

          if (value.isNotEmpty && value != _barcodeResult) {
            _barcodeResult = value;
            _barcodeFormat = barcode.format;

            SystemSound.play(SystemSoundType.click);
            await _cameraController?.stopImageStream();
            _streamStopped = true;

            if (mounted) setState(() {});
          }
        }
      }
    } catch (e) {
      debugPrint('Lỗi xử lý ảnh: $e');
    } finally {
      _isBusy = false;
    }
  }

  // Thay thế method _convertCameraImage
  InputImage? _convertCameraImage(CameraImage image) {
    try {
      // Sử dụng tất cả bytes từ planes
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final rotation = _getImageRotation();

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: rotation,
          format: InputImageFormat.yuv420,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('Lỗi convert image: $e');
      return null;
    }
  }

  // Sửa method _getImageRotation
  InputImageRotation _getImageRotation() {
    if (_cameraController == null) return InputImageRotation.rotation0deg;

    final sensorOrientation = _cameraController!.description.sensorOrientation;

    // Xử lý rotation dựa trên device orientation
    int rotationCompensation = sensorOrientation;

    // Đối với hầu hết Android devices, camera sensor thường là 90 độ
    // Cần compensate cho portrait mode
    if (sensorOrientation == 90) {
      rotationCompensation = 90;
    } else if (sensorOrientation == 270) {
      rotationCompensation = 270;
    }

    switch (rotationCompensation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation90deg; // Default cho Android
    }
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null) return;

    try {
      _isFlashOn = !_isFlashOn;
      await _cameraController!.setFlashMode(
        _isFlashOn ? FlashMode.torch : FlashMode.off,
      );
      setState(() {});
    } catch (e) {
      debugPrint('Lỗi toggle flash: $e');
    }
  }

  Future<void> _restartScanning() async {
    if (_cameraController == null) return;

    try {
      _barcodeResult = null;
      _barcodeFormat = null;
      _streamStopped = false;
      _isBusy = false;

      if (!_cameraController!.value.isStreamingImages) {
        await _cameraController!.startImageStream(_processCameraImage);
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Lỗi restart scanning: $e');
    }
  }

  String _getBarcodeFormatName(BarcodeFormat? format) {
    switch (format) {
      case BarcodeFormat.qrCode:
        return 'QR Code';
      case BarcodeFormat.ean13:
        return 'EAN-13';
      case BarcodeFormat.ean8:
        return 'EAN-8';
      case BarcodeFormat.code128:
        return 'Code 128';
      case BarcodeFormat.code39:
        return 'Code 39';
      default:
        return 'Barcode';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready =
        _cameraController != null && _cameraController!.value.isInitialized;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quét mã vạch'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          if (ready)
            IconButton(
              onPressed: _toggleFlash,
              icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
            ),
        ],
      ),
      body: !ready
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Đang khởi tạo camera...'),
                ],
              ),
            )
          : Stack(
              children: [
                // Camera preview full screen
                SizedBox.expand(child: CameraPreview(_cameraController!)),

                // Khung quét
                Center(
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _barcodeResult != null
                            ? Colors.green
                            : Colors.red,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                // Hướng dẫn
                if (_barcodeResult == null)
                  Positioned(
                    top: 100,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Đưa mã vạch vào khung đỏ để quét\nGiữ camera ổn định',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),

                // Kết quả
                if (_barcodeResult != null)
                  Positioned(
                    bottom: 40,
                    left: 20,
                    right: 20,
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Quét thành công!',
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Loại: ${_getBarcodeFormatName(_barcodeFormat)}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                _barcodeResult!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: _barcodeResult!),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Đã copy!')),
                                  );
                                },
                                icon: const Icon(Icons.copy),
                                label: const Text('Copy'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _restartScanning,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Quét lại'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
