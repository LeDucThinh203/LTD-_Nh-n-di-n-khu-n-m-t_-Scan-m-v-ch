import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FacePainter extends CustomPainter {
  final List<Face> faces;
  final Size previewSize; // size raw từ camera (landscape orientation)
  final bool isFront;
  final InputImageRotation rotation;
  final bool showDebug;

  FacePainter(
    this.faces,
    this.previewSize, {
    this.isFront = false,
    this.rotation = InputImageRotation.rotation0deg,
    this.showDebug = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Tùy rotation của camera, width/height có thể hoán đổi.
    late double scaleX;
    late double scaleY;
    final bool swapped =
        rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    if (swapped) {
      scaleX = size.width / previewSize.height;
      scaleY = size.height / previewSize.width;
    } else {
      scaleX = size.width / previewSize.width;
      scaleY = size.height / previewSize.height;
    }

    final rectPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.greenAccent;

    final bgLabelPaint = Paint()..color = Colors.black.withOpacity(.45);

    final textPainter = TextPainter(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    );

    for (final face in faces) {
      // Mirror cho camera trước
      double left = face.boundingBox.left;
      double right = face.boundingBox.right;
      if (isFront) {
        if (swapped) {
          // swapped => width của preview là height thực tế
          left = previewSize.height - face.boundingBox.right;
          right = previewSize.height - face.boundingBox.left;
        } else {
          left = previewSize.width - face.boundingBox.right;
          right = previewSize.width - face.boundingBox.left;
        }
      }

      final top = face.boundingBox.top;
      final bottom = face.boundingBox.bottom;

      final rect = Rect.fromLTRB(
        left * scaleX,
        top * scaleY,
        right * scaleX,
        bottom * scaleY,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        rectPaint,
      );

      // Smile label
      String label = '';
      final smile = face.smilingProbability;
      if (smile != null) {
        final percent = (smile * 100).round();
        if (percent >= 65) {
          label = '😄 Cười $percent%';
        } else if (percent >= 35) {
          label = '� Bình thường $percent%';
        } else if (percent >= 10) {
          label = '😐 Trầm $percent%';
        } else {
          label = '😶 Neutral';
        }
      } else if (showDebug) {
        label = 'No smile prob';
      }

      if (label.isNotEmpty) {
        textPainter.text = TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        );
        textPainter.layout();
        final tp = Offset(
          rect.left,
          rect.top - (textPainter.height + 6) < 0
              ? rect.top + 4
              : rect.top - (textPainter.height + 6),
        );
        final bgRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            tp.dx - 6,
            tp.dy - 3,
            textPainter.width + 12,
            textPainter.height + 6,
          ),
          const Radius.circular(8),
        );
        canvas.drawRRect(bgRect, bgLabelPaint);
        textPainter.paint(canvas, tp);
      }

      if (showDebug) {
        final dbg = 'sm=${smile?.toStringAsFixed(2)}';
        textPainter.text = TextSpan(
          text: dbg,
          style: const TextStyle(color: Colors.yellowAccent, fontSize: 11),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          rect.bottomRight -
              Offset(textPainter.width + 4, textPainter.height + 4),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant FacePainter old) =>
      old.faces != faces ||
      old.isFront != isFront ||
      old.rotation != rotation ||
      old.showDebug != showDebug;
}
