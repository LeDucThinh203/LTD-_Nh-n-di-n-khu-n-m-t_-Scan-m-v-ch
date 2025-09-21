import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

class FaceScanRecognitionPage extends StatefulWidget {
  const FaceScanRecognitionPage({Key? key}) : super(key: key);

  @override
  State<FaceScanRecognitionPage> createState() => _FaceScanRecognitionPageState();
}

class _FaceScanRecognitionPageState extends State<FaceScanRecognitionPage> {
  CameraController? _cameraController;
  late FaceDetector _faceDetector;
  bool _isDetecting = false;
  List<Face> _faces = [];
  XFile? _lastCapturedImage;

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
        orElse: () => cameras.first);

    _cameraController = CameraController(camera, ResolutionPreset.medium);
    await _cameraController!.initialize();
    _cameraController!.startImageStream(_processCameraImage);

    if (mounted) setState(() {});
  }

  void _initFaceDetector() {
    _faceDetector = FaceDetector(
        options: FaceDetectorOptions(enableContours: false, enableClassification: true));
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting) return;
    _isDetecting = true;

    try {
      final bytes = Uint8List.fromList(
          image.planes.fold<List<int>>([], (buffer, plane) => buffer..addAll(plane.bytes)));

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      final faces = await _faceDetector.processImage(inputImage);
      if (mounted) setState(() => _faces = faces);
    } catch (e) {
      print("Lỗi xử lý ảnh: $e");
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
        final filePath = '${personDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File(filePath);
        await file.writeAsBytes(await image.readAsBytes());
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        print("Lỗi khi chụp ảnh: $e");
        i--; // thử lại
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Quét thành công! 10 ảnh đã được lưu")));
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

  Future<void> _recognizeFace() async {
    final image = await _cameraController!.takePicture();
    _lastCapturedImage = image;

    final faces = await _faceDetector.processImage(InputImage.fromFilePath(image.path));
    if (faces.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Không phát hiện khuôn mặt")));
      return;
    }

    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/faces');
    if (!dir.existsSync()) return;

    Map<String, double> results = {};

    for (var personDir in dir.listSync()) {
      if (personDir is Directory) {
        double maxScore = 0;
        for (var file in personDir.listSync()) {
          if (file is File) {
            final storedFaces =
                await _faceDetector.processImage(InputImage.fromFilePath(file.path));
            if (storedFaces.isEmpty) continue;
            double score = _compareFaces(faces.first, storedFaces.first);
            if (score > maxScore) maxScore = score;
          }
        }
        results[personDir.path.split('/').last] = maxScore;
      }
    }

    String message = results.entries
        .map((e) => "${e.key}: ${e.value.toStringAsFixed(1)}%")
        .join(", ");
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  double _compareFaces(Face f1, Face f2) {
    double boxScore = 100 -
        ((f1.boundingBox.width - f2.boundingBox.width).abs() +
                (f1.boundingBox.height - f2.boundingBox.height).abs()) / 2;
    double smile1 = f1.smilingProbability ?? 0;
    double smile2 = f2.smilingProbability ?? 0;
    double smileScore = 100 - ((smile1 - smile2).abs() * 100);
    return ((boxScore + smileScore) / 2).clamp(0, 100);
  }

  Future<void> _viewSavedFaces() async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/faces');
    if (!dir.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Chưa có dữ liệu scan nào.")));
      return;
    }

    final persons = dir.listSync().whereType<Directory>().toList();

    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => Scaffold(
                  appBar: AppBar(title: const Text("Danh sách người")),
                  body: ListView.builder(
                    itemCount: persons.length,
                    itemBuilder: (context, index) {
                      final personDir = persons[index];
                      final personName = personDir.path.split('/').last;
                      return ListTile(
                        title: Text(personName),
                        onTap: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      _PersonImagesPage(personDir)));
                        },
                        onLongPress: () async {
                          bool? confirm = await showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text("Xác nhận xoá folder"),
                              content: Text(
                                  "Bạn có chắc muốn xoá toàn bộ folder '$personName' và tất cả ảnh bên trong?"),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text("Hủy")),
                                TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text("Xoá")),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            await personDir.delete(recursive: true);
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Folder '$personName' đã bị xoá")));
                          }
                        },
                      );
                    },
                  ),
                )));
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
      appBar: AppBar(title: const Text("Scan & Nhận diện khuôn mặt")),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraController!),
          CustomPaint(painter: FacePainter(_faces, _cameraController!.value.previewSize!)),
          Positioned(
            bottom: 180,
            left: 20,
            child: ElevatedButton(
              onPressed: _viewSavedFaces,
              child: const Text("Xem ảnh đã lưu"),
            ),
          ),
          Positioned(
            bottom: 120,
            left: 20,
            child: ElevatedButton(
              onPressed: _scanAndSaveFaces,
              child: const Text("Scan & Lưu"),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 20,
            child: ElevatedButton(
              onPressed: _recognizeFace,
              child: const Text("So sánh & Nhận diện"),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonImagesPage extends StatefulWidget {
  final Directory personDir;
  const _PersonImagesPage(this.personDir, {Key? key}) : super(key: key);

  @override
  State<_PersonImagesPage> createState() => _PersonImagesPageState();
}

class _PersonImagesPageState extends State<_PersonImagesPage> {
  late List<File> files;

  @override
  void initState() {
    super.initState();
    files = widget.personDir.listSync().whereType<File>().toList();
  }

  Future<void> _deleteImage(File file) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Xác nhận xoá"),
        content: const Text("Bạn có chắc muốn xoá ảnh này?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Hủy")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Xoá")),
        ],
      ),
    );

    if (confirm == true) {
      await file.delete();
      setState(() {
        files.remove(file);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.personDir.path.split('/').last)),
      body: GridView.builder(
        gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2),
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index];
          return GestureDetector(
            onLongPress: () => _deleteImage(file),
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Image.file(File(file.path), fit: BoxFit.cover),
            ),
          );
        },
      ),
    );
  }
}

class FacePainter extends CustomPainter {
  final List<Face> faces;
  final Size previewSize;
  FacePainter(this.faces, this.previewSize);

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / previewSize.height;
    final double scaleY = size.height / previewSize.width;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.red;

    final textPainter = TextPainter(textAlign: TextAlign.left, textDirection: TextDirection.ltr);

    for (Face face in faces) {
      final rect = Rect.fromLTRB(
          face.boundingBox.left * scaleX,
          face.boundingBox.top * scaleY,
          face.boundingBox.right * scaleX,
          face.boundingBox.bottom * scaleY);
      canvas.drawRect(rect, paint);

      String label = "";
      if (face.smilingProbability != null) {
        int percent = (face.smilingProbability! * 100).toInt();
        label = percent > 50 ? "Vui $percent%" : "Buồn ${100 - percent}%";
      }

      textPainter.text = TextSpan(
          text: label,
          style: const TextStyle(color: Colors.blue, fontSize: 16, fontWeight: FontWeight.bold));
      textPainter.layout();
      textPainter.paint(canvas, Offset(rect.left, rect.top > 20 ? rect.top - 20 : rect.top));
    }
  }

  @override
  bool shouldRepaint(covariant FacePainter oldDelegate) => oldDelegate.faces != faces;
}
