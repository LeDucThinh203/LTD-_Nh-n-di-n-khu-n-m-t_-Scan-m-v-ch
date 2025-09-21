import 'package:flutter/material.dart';
import 'face_scan_recognition_page.dart'; // import file mới vừa tạo

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FaceScanRecognitionPage(), // chạy page có 2 nút
    );
  }
}
