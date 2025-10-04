import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:url_launcher/url_launcher.dart';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({Key? key}) : super(key: key);

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> with WidgetsBindingObserver {
  CameraController? _cameraController;
  late final BarcodeScanner _barcodeScanner;
  bool _isBusy = false;
  String? _barcodeResult;
  BarcodeFormat? _barcodeFormat;
  bool _streamStopped = false;
  bool _isFlashOn = false;
  CameraDescription? _currentCamera;
  DateTime? _lastProcessTime;
  static const Duration _processingInterval = Duration(milliseconds: 100);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _barcodeScanner = BarcodeScanner(
      formats: BarcodeFormat.values,
    );
    _initCamera();
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
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(_currentCamera?.lensDirection ?? CameraLensDirection.back);
    }
  }

  Future<void> _initCamera([CameraLensDirection direction = CameraLensDirection.back]) async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('Không tìm thấy camera');

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == direction,
        orElse: () => cameras.first,
      );

      _currentCamera = camera;

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      await _cameraController!.setFocusMode(FocusMode.auto);
      await _cameraController!.setExposureMode(ExposureMode.auto);
      await _cameraController!.startImageStream(_processCameraImage);

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Lỗi khởi tạo camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi camera: $e\nVui lòng cấp quyền camera trong Settings'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isBusy || _streamStopped) return;

    final now = DateTime.now();
    if (_lastProcessTime != null && now.difference(_lastProcessTime!) < _processingInterval) return;
    _lastProcessTime = now;

    _isBusy = true;
    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage != null) {
        final barcodes = await _barcodeScanner.processImage(inputImage);
        if (barcodes.isNotEmpty && mounted) {
          final barcode = barcodes.first;
          final value = barcode.rawValue ?? '';
          if (value.isNotEmpty && value != _barcodeResult) {
            _barcodeResult = value;
            _barcodeFormat = barcode.format;
            SystemSound.play(SystemSoundType.click);
            await _cameraController?.stopImageStream();
            _streamStopped = true;
            setState(() {});
          }
        }
      }
    } catch (e) {
      debugPrint('Lỗi xử lý ảnh: $e');
    } finally {
      _isBusy = false;
    }
  }

  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final allBytes = WriteBuffer();
      for (final plane in image.planes) {
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

  InputImageRotation _getImageRotation() {
    if (_cameraController == null) return InputImageRotation.rotation0deg;
    switch (_cameraController!.description.sensorOrientation) {
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

  Future<void> _toggleFlash() async {
    if (_cameraController == null) return;
    try {
      _isFlashOn = !_isFlashOn;
      await _cameraController!.setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    } catch (e) {
      debugPrint('Lỗi toggle flash: $e');
    }
  }

  Future<void> _restartScanning() async {
    if (_cameraController == null) return;
    _barcodeResult = null;
    _barcodeFormat = null;
    _streamStopped = false;
    _isBusy = false;
    if (!_cameraController!.value.isStreamingImages) {
      await _cameraController!.startImageStream(_processCameraImage);
    }
    setState(() {});
  }

  Future<void> _switchCamera() async {
    if (_currentCamera == null) return;
    final newDirection = _currentCamera!.lensDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;

    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();

    _streamStopped = false;
    _barcodeResult = null;
    _barcodeFormat = null;
    _isBusy = false;
    _isFlashOn = false;

    await _initCamera(newDirection);
  }

  bool _isLink(String text) => RegExp(r'^(http|https)://', caseSensitive: false).hasMatch(text);

  String _formatBarcodeName(BarcodeFormat? format) {
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
      case BarcodeFormat.upca:
        return 'UPC-A';
      case BarcodeFormat.upce:
        return 'UPC-E';
      default:
        return 'Barcode';
    }
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    // Cố gắng mở bằng Chrome trên Android nếu có, fallback vào default
    final chromePackage = 'com.android.chrome';
    if (await canLaunchUrl(uri)) {
      if (Theme.of(context).platform == TargetPlatform.android) {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication, webViewConfiguration: const WebViewConfiguration(), webOnlyWindowName: '_blank');
          // Không có cách bắt buộc mở bằng Chrome từ url_launcher chuẩn, 
          // nhưng mode externalApplication sẽ dùng app tương ứng (Chrome nếu cài)
        } catch (_) {
          await launchUrl(uri);
        }
      } else {
        await launchUrl(uri);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể mở liên kết')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _cameraController?.value.isInitialized ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quét mã vạch'),
        backgroundColor: Colors.black87,
        actions: [
          if (ready)
            IconButton(
              onPressed: _toggleFlash,
              icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
            ),
          if (ready)
            IconButton(
              onPressed: _switchCamera,
              icon: const Icon(Icons.cameraswitch),
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
                SizedBox.expand(child: CameraPreview(_cameraController!)),
                Center(
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _barcodeResult != null ? Colors.green : Colors.red,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
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
                                children: const [
                                  Icon(Icons.check_circle, color: Colors.green),
                                  SizedBox(width: 8),
                                  Text(
                                    'Quét thành công!',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Loại: ${_barcodeFormat != null ? _formatBarcodeName(_barcodeFormat) : 'Unknown'}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                _barcodeResult!,
                                style: const TextStyle(color: Colors.white, fontSize: 16),
                              ),
                              if (_isLink(_barcodeResult!))
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => _launchUrl(_barcodeResult!),
                                    icon: const Icon(Icons.open_in_browser),
                                    label: const Text('Mở liên kết'),
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
                                  Clipboard.setData(ClipboardData(text: _barcodeResult!));
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
