import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

typedef OnImageAvailable = Future<void> Function(CameraImageWrapper image);
typedef OnCameraError = void Function(dynamic error);

class CameraImageWrapper {
  final CameraImage image;
  final InputImageRotation rotation;

  CameraImageWrapper(this.image, this.rotation);
}

enum InputImageRotation {
  rotation0deg,
  rotation90deg,
  rotation180deg,
  rotation270deg,
}

class CameraManager {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  CameraLensDirection _currentLensDirection = CameraLensDirection.back;
  bool isFlashOn = false;

  final OnImageAvailable onImage;
  final OnCameraError onError;

  bool isInitialized = false;

  CameraManager({required this.onImage, required this.onError});

  Future<void> initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isEmpty) {
        throw Exception('Không tìm thấy camera');
      }
      await _initController();
    } catch (e) {
      onError(e);
    }
  }

  Future<void> _initController() async {
    final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == _currentLensDirection,
        orElse: () => _cameras!.first);
    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller!.initialize();

    await _controller!.setFocusMode(FocusMode.auto);
    await _controller!.setExposureMode(ExposureMode.auto);

    await startImageStream();

    isInitialized = true;
  }

  Future<void> startImageStream() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (!_controller!.value.isStreamingImages) {
      await _controller!.startImageStream(_processCameraImage);
    }
  }

  Future<void> stopImageStream() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
  }

  void toggleFlash() {
    if (_controller == null) return;

    isFlashOn = !isFlashOn;
    _controller!.setFlashMode(isFlashOn ? FlashMode.torch : FlashMode.off);
  }

  Future<void> switchCamera() async {
    if (_cameras == null || _cameras!.isEmpty) return;

    _currentLensDirection = _currentLensDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;

    await stopImageStream();
    await _controller?.dispose();

    isInitialized = false;
    await _initController();
  }

  Widget buildPreview() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return CameraPreview(_controller!);
  }

  void dispose() {
    _controller?.dispose();
  }

  bool _isBusy = false;

  void _processCameraImage(CameraImage image) async {
    if (_isBusy) return;
    _isBusy = true;

    try {
      final rotation = _getImageRotation();
      await onImage(CameraImageWrapper(image, rotation));
    } catch (e) {
      onError(e);
    } finally {
      _isBusy = false;
    }
  }

  InputImageRotation _getImageRotation() {
    if (_controller == null) return InputImageRotation.rotation0deg;

    final sensorOrientation = _controller!.description.sensorOrientation;

    switch (sensorOrientation) {
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
}
