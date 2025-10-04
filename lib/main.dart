import 'package:flutter/material.dart';
import 'package:quan_ly_sinh_vien/scanner_page.dart';
import 'package:quan_ly_sinh_vien/barcode_scanner_page.dart' hide BarcodeScannerPage;
import 'scan_save_page.dart';
import 'recognize_page.dart';
import 'view_saved_faces_page.dart';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Nhận diện khuôn mặt & Quét mã")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const BarcodeScannerPage())),
              child: const Text("📸 Scan & Lưu 10 ảnh"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const RecognizePage())),
              child: const Text("🤖 So sánh & Nhận diện"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const ViewSavedFacesPage())),
              child: const Text("🖼 Xem ảnh đã lưu"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const BarcodeScannerPage())),
              child: const Text("📷 Quét mã vạch / QR"),
            ),
          ],
        ),
      ),
    );
  }
}
