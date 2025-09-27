import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';


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
        label = percent > 50 ? "😊 Vui $percent%" : "😐 Buồn ${100 - percent}%";
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
