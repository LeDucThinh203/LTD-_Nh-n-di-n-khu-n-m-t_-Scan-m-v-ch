import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';
import 'camera_manager.dart' hide InputImageRotation;

class BarcodeScanResult {
  final String value;
  final BarcodeFormat format;

  BarcodeScanResult(this.value, this.format);
}

class BarcodeDetector {
  final BarcodeScanner _scanner = BarcodeScanner(
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

  Future<BarcodeScanResult?> processImage(CameraImageWrapper wrapper) async {
    final inputImage = _convertCameraImage(wrapper.image, wrapper.rotation as InputImageRotation);
    if (inputImage == null) return null;

    final barcodes = await _scanner.processImage(inputImage);

    if (barcodes.isEmpty) return null;

    final barcode = barcodes.first;
    final value = barcode.rawValue ?? '';

    if (value.isEmpty) return null;

    return BarcodeScanResult(value, barcode.format);
  }

  Future<BarcodeScanResult?> pickImageAndScan() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return null;

      final inputImage = InputImage.fromFilePath(pickedFile.path);

      final barcodes = await _scanner.processImage(inputImage);
      if (barcodes.isEmpty) return null;

      final barcode = barcodes.first;
      final value = barcode.rawValue ?? '';

      if (value.isEmpty) return null;

      return BarcodeScanResult(value, barcode.format);
    } catch (e) {
      debugPrint('Lỗi chọn ảnh hoặc xử lý ảnh: $e');
      return null;
    }
  }

  void dispose() {
    _scanner.close();
  }

  String getFormatName(BarcodeFormat? format) {
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

  InputImage? _convertCameraImage(
      CameraImage image, InputImageRotation rotation) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final imageSize = Size(image.width.toDouble(), image.height.toDouble());

      final inputImageFormat = InputImageFormat.yuv420;

      final inputImageRotation = _mapRotation(rotation);

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: inputImageRotation,
          format: inputImageFormat,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('Lỗi convert image: $e');
      return null;
    }
  }

  InputImageRotation _mapRotation(InputImageRotation rotation) {
    switch (rotation) {
      case InputImageRotation.rotation0deg:
        return InputImageRotation.rotation0deg;
      case InputImageRotation.rotation90deg:
        return InputImageRotation.rotation90deg;
      case InputImageRotation.rotation180deg:
        return InputImageRotation.rotation180deg;
      case InputImageRotation.rotation270deg:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }
}
