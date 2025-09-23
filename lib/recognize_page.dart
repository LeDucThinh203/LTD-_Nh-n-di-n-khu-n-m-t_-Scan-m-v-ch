import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class RecognizePage extends StatefulWidget {
  const RecognizePage({Key? key}) : super(key: key);

  @override
  State<RecognizePage> createState() => _RecognizePageState();
}

class _RecognizePageState extends State<RecognizePage> {
  CameraController? _cameraController;
  late FaceDetector _faceDetector;

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

    _cameraController = CameraController(camera, ResolutionPreset.medium);
    await _cameraController!.initialize();
    if (mounted) setState(() {});
  }

  void _initFaceDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableClassification: false, // bỏ smile probability để ổn định hơn
      ),
    );
  }

  Future<void> _recognizeFromCamera() async {
    try {
      final image = await _cameraController!.takePicture();
      await _recognizeFaceFromFile(File(image.path));
    } catch (e) {
      debugPrint("Lỗi nhận diện từ camera: $e");
    }
  }

  Future<void> _recognizeFromGallery() async {
    try {
      final pickedImage =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (pickedImage != null) {
        await _recognizeFaceFromFile(File(pickedImage.path));
      }
    } catch (e) {
      debugPrint("Lỗi nhận diện từ thư viện: $e");
    }
  }

  Future<void> _recognizeFaceFromFile(File file) async {
    try {
      final faces =
          await _faceDetector.processImage(InputImage.fromFilePath(file.path));

      if (faces.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("❌ Không phát hiện khuôn mặt")));
        return;
      }

      final dir =
          Directory('${(await getApplicationDocumentsDirectory()).path}/faces');
      if (!dir.existsSync()) return;

      Map<String, double> results = {};

      for (var personDir in dir.listSync()) {
        if (personDir is Directory) {
          double maxScore = 0;
          for (var storedFile in personDir.listSync().whereType<File>()) {
            final storedFaces = await _faceDetector
                .processImage(InputImage.fromFilePath(storedFile.path));
            if (storedFaces.isEmpty) continue;
            double score = _compareFaces(faces.first, storedFaces.first);
            if (score > maxScore) maxScore = score;
          }
          results[personDir.path.split('/').last] = maxScore;
        }
      }

      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("❌ Không có dữ liệu để so sánh")));
        return;
      }

      final bestMatch = results.entries.reduce((a, b) => a.value > b.value ? a : b);
      String message =
          "✅ Giống nhất: ${bestMatch.key} (${bestMatch.value.toStringAsFixed(1)}%)";

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      debugPrint("Lỗi nhận diện khuôn mặt: $e");
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Lỗi khi nhận diện khuôn mặt")));
    }
  }

  // So sánh bounding box tỉ lệ, bỏ smile
  double _compareFaces(Face f1, Face f2) {
    double w1 = f1.boundingBox.width;
    double h1 = f1.boundingBox.height;
    double w2 = f2.boundingBox.width;
    double h2 = f2.boundingBox.height;

    double widthScore = 100 - ((w1 - w2).abs() / ((w1 + w2) / 2) * 100);
    double heightScore = 100 - ((h1 - h2).abs() / ((h1 + h2) / 2) * 100);

    return ((widthScore + heightScore) / 2).clamp(0, 100);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Widget _buildRoundButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.blueAccent,
      shape: const CircleBorder(),
      elevation: 6,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 60,
          height: 60,
          child: Icon(icon, color: Colors.white, size: 30),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("🤖 Nhận diện khuôn mặt")),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraController!),
          Positioned(
            bottom: 100,
            right: 30,
            child: _buildRoundButton(
              icon: Icons.camera_alt,
              onTap: _recognizeFromCamera,
            ),
          ),
          Positioned(
            bottom: 30,
            right: 30,
            child: _buildRoundButton(
              icon: Icons.photo_library,
              onTap: _recognizeFromGallery,
            ),
          ),
        ],
      ),
    );
  }
}
