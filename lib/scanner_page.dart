import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({Key? key}) : super(key: key);

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  late final BarcodeScanner _barcodeScanner;
  bool _isBusy = false;
  String? _barcodeResult;
  BarcodeFormat? _barcodeFormat;
  bool _streamStopped = false;
  bool _isFlashOn = false;
  final ImagePicker _imagePicker = ImagePicker();
  String? _pickedImagePath; // Lưu đường dẫn ảnh đã chọn để hiển thị lại
  late final AnimationController _scanLineController; // Animation line quét
  static const double _frameSize = 280;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
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
    _scanLineController.dispose();
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

  Future<void> _pickImageAndScan() async {
    try {
      // Chọn ảnh từ thư viện
      final XFile? imageFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (imageFile == null) return; // người dùng hủy

      // Lưu ảnh để hiển thị
      _pickedImagePath = imageFile.path;
      if (mounted) setState(() {});

      // Tạm dừng stream để tránh xử lý song song
      if (_cameraController?.value.isStreamingImages ?? false) {
        try {
          await _cameraController?.stopImageStream();
          _streamStopped = true;
        } catch (_) {}
      }

      setState(() => _isBusy = true);

      final inputImage = InputImage.fromFilePath(imageFile.path);
      final barcodes = await _barcodeScanner.processImage(inputImage);

      if (barcodes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không tìm thấy mã trong ảnh.')),
          );
        }
        // Giữ nguyên ảnh trên màn hình để người dùng nhìn thấy
        return; // không xóa _pickedImagePath
      }

      // Lấy barcode đầu tiên
      final barcode = barcodes.first;
      _barcodeResult = barcode.rawValue;
      _barcodeFormat = barcode.format;
      SystemSound.play(SystemSoundType.click);

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Lỗi quét ảnh: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi đọc ảnh: $e')));
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _restartScanning() async {
    if (_cameraController == null) return;

    try {
      _barcodeResult = null;
      _barcodeFormat = null;
      _streamStopped = false;
      _isBusy = false;
      _pickedImagePath = null; // Quay lại camera nên xóa ảnh đã chọn

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

  bool get _isResultUrl {
    final v = _normalizedUrlCandidate();
    if (v == null) return false;
    return v.scheme == 'http' || v.scheme == 'https';
  }

  Future<void> _openUrl() async {
    if (!_isResultUrl) return;
    final uri = _normalizedUrlCandidate()!;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Không mở được link')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi mở link: $e')));
      }
    }
  }

  Uri? _normalizedUrlCandidate() {
    final raw = _barcodeResult;
    if (raw == null) return null;
    // Loại bỏ mọi khoảng trắng & xuống dòng ở giữa (QR đôi khi chứa line break)
    final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Nếu có khoảng trắng (giữa các từ) => không phải URL hợp lệ
    if (cleaned.contains(' ')) return null;
    String candidate = cleaned;
    if (!candidate.startsWith('http://') && !candidate.startsWith('https://')) {
      candidate = 'https://$candidate';
    }
    try {
      final uri = Uri.parse(candidate);
      if (uri.host.isEmpty) return null;
      return uri;
    } catch (_) {
      return null;
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
          if (ready)
            IconButton(
              tooltip: 'Chọn ảnh từ thư viện',
              onPressed: _pickImageAndScan,
              icon: const Icon(Icons.image),
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
                // Hiển thị camera hoặc ảnh đã chọn
                if (_pickedImagePath == null)
                  SizedBox.expand(child: CameraPreview(_cameraController!))
                else
                  Positioned.fill(
                    child: Image.file(
                      File(_pickedImagePath!),
                      fit: BoxFit.cover,
                    ),
                  ),

                // Khung quét
                if (_pickedImagePath == null)
                  Center(
                    child: SizedBox(
                      width: _frameSize,
                      height: _frameSize,
                      child: Stack(
                        children: [
                          // Khung viền
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _barcodeResult != null
                                    ? Colors.greenAccent
                                    : Colors.white.withOpacity(0.9),
                                width: 2.2,
                              ),
                            ),
                          ),
                          // Góc highlight
                          ..._buildCorners(),
                          // Scan line
                          AnimatedBuilder(
                            animation: _scanLineController,
                            builder: (context, _) {
                              final pos =
                                  _scanLineController.value * (_frameSize - 4);
                              return Positioned(
                                top: pos,
                                left: 0,
                                right: 0,
                                child: Container(
                                  height: 4,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        Colors.redAccent.withOpacity(0.85),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                // Hướng dẫn
                if (_barcodeResult == null && _pickedImagePath == null)
                  Positioned(
                    top: 95,
                    left: 24,
                    right: 24,
                    child: _InfoBanner(
                      text: _isBusy
                          ? 'Đang xử lý...' // hiển thị khi đang busy
                          : 'Căn mã vào khung – giữ thiết bị ổn định',
                      icon: Icons.qr_code_scanner,
                    ),
                  ),
                if (_barcodeResult == null && _pickedImagePath != null)
                  Positioned(
                    top: 95,
                    left: 24,
                    right: 24,
                    child: const _InfoBanner(
                      text:
                          'Ảnh đã chọn – nếu chưa nhận ra mã, thử ảnh khác hoặc Quét lại',
                      icon: Icons.image_outlined,
                    ),
                  ),

                // Kết quả
                if (_barcodeResult != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 24,
                    child: _ResultPanel(
                      result: _barcodeResult!,
                      format: _getBarcodeFormatName(_barcodeFormat),
                      isUrl: _isResultUrl,
                      onOpenUrl: _openUrl,
                      onCopy: () {
                        Clipboard.setData(ClipboardData(text: _barcodeResult!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Đã copy!')),
                        );
                      },
                      onRescan: _restartScanning,
                      onPickImage: _pickImageAndScan,
                    ),
                  ),
              ],
            ),
    );
  }

  // Tạo các góc sáng cho khung quét
  List<Widget> _buildCorners() {
    const double corner = 26;
    final color = _barcodeResult != null
        ? Colors.greenAccent
        : Colors.redAccent;
    BorderSide side = BorderSide(color: color, width: 3);
    return [
      Positioned(
        top: 0,
        left: 0,
        child: SizedBox(
          width: corner,
          height: corner,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: side, left: side),
            ),
          ),
        ),
      ),
      Positioned(
        top: 0,
        right: 0,
        child: SizedBox(
          width: corner,
          height: corner,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: side, right: side),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: 0,
        left: 0,
        child: SizedBox(
          width: corner,
          height: corner,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: side, left: side),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: 0,
        right: 0,
        child: SizedBox(
          width: corner,
          height: corner,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: side, right: side),
            ),
          ),
        ),
      ),
    ];
  }
}

// Banner hướng dẫn tái sử dụng
class _InfoBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  const _InfoBanner({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    height: 1.25,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Panel kết quả dạng glass
class _ResultPanel extends StatelessWidget {
  final String result;
  final String format;
  final bool isUrl;
  final VoidCallback onOpenUrl;
  final VoidCallback onCopy;
  final VoidCallback onRescan;
  final VoidCallback onPickImage;
  const _ResultPanel({
    required this.result,
    required this.format,
    required this.isUrl,
    required this.onOpenUrl,
    required this.onCopy,
    required this.onRescan,
    required this.onPickImage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.10),
                Colors.white.withOpacity(0.04),
              ],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.verified, color: Colors.greenAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quét thành công',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Loại: $format',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: isUrl ? onOpenUrl : null,
                child: Text(
                  result,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isUrl ? Colors.lightBlueAccent : Colors.white,
                    fontSize: 15.5,
                    height: 1.3,
                    decoration: isUrl ? TextDecoration.underline : null,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _actionChip(Icons.copy, 'Copy', onCopy),
                  _actionChip(Icons.refresh, 'Quét lại', onRescan),
                  _actionChip(Icons.image_search, 'Ảnh khác', onPickImage),
                  if (isUrl)
                    _actionChip(Icons.open_in_browser, 'Mở link', onOpenUrl),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}
