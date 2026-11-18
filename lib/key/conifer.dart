import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:flutter/material.dart';

String guideLeafName(S strings, String id) {
  switch (id) {
    case '1':
      return strings.guide_leaf_bundle;
    case '2':
      return strings.guide_leaf_single;
    case '3':
      return strings.guide_leaf_tuft;
    case '4':
      return strings.guide_leaf_scale;
    case '5':
      return strings.guide_leaf_fan;
    default:
      return '';
  }
}

String guideLeafExample(S strings, String id) {
  switch (id) {
    case '1':
      return strings.guide_leaf_bundle_ex;
    case '2':
      return strings.guide_leaf_single_ex;
    case '3':
      return strings.guide_leaf_tuft_ex;
    case '4':
      return strings.guide_leaf_scale_ex;
    case '5':
      return strings.guide_leaf_fan_ex;
    default:
      return '';
  }
}

String guideConeName(S strings, String id) {
  switch (id) {
    case '1':
      return strings.guide_cone_long;
    case '2':
      return strings.guide_cone_round;
    case '3':
      return strings.guide_cone_berry;
    default:
      return '';
  }
}

String guideConeExample(S strings, String id) {
  switch (id) {
    case '1':
      return strings.guide_cone_long_ex;
    case '2':
      return strings.guide_cone_round_ex;
    case '3':
      return strings.guide_cone_berry_ex;
    default:
      return '';
  }
}

class GuideLeafGlyph extends StatelessWidget {
  final String id;
  final double size;

  const GuideLeafGlyph({super.key, required this.id, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LeafPainter(id, colors.moss)),
    );
  }
}

class GuideConeGlyph extends StatelessWidget {
  final String id;
  final double size;

  const GuideConeGlyph({super.key, required this.id, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ConePainter(id, colors.moss)),
    );
  }
}

class _LeafPainter extends CustomPainter {
  final String id;
  final Color moss;

  _LeafPainter(this.id, this.moss);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 46, size.height / 46);
    final paint = Paint()
      ..color = moss
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (id) {
      case '1':
        canvas.drawLine(const Offset(23, 38), const Offset(23, 22), paint);
        canvas.drawLine(const Offset(23, 22), const Offset(10, 8), paint);
        canvas.drawLine(const Offset(23, 22), const Offset(23, 5), paint);
        canvas.drawLine(const Offset(23, 22), const Offset(36, 8), paint);
      case '2':
        canvas.drawLine(const Offset(23, 40), const Offset(23, 6), paint);
        canvas.drawLine(const Offset(23, 14), const Offset(10, 8), paint);
        canvas.drawLine(const Offset(23, 20), const Offset(36, 14), paint);
        canvas.drawLine(const Offset(23, 26), const Offset(10, 22), paint);
        canvas.drawLine(const Offset(23, 32), const Offset(36, 28), paint);
      case '3':
        canvas.drawLine(const Offset(14, 40), const Offset(14, 20), paint);
        canvas.drawLine(const Offset(14, 20), const Offset(6, 10), paint);
        canvas.drawLine(const Offset(14, 20), const Offset(14, 6), paint);
        canvas.drawLine(const Offset(14, 20), const Offset(22, 10), paint);
        canvas.drawLine(const Offset(32, 40), const Offset(32, 20), paint);
        canvas.drawLine(const Offset(32, 20), const Offset(24, 10), paint);
        canvas.drawLine(const Offset(32, 20), const Offset(32, 6), paint);
        canvas.drawLine(const Offset(32, 20), const Offset(40, 10), paint);
      case '4':
        canvas.drawLine(const Offset(23, 5), const Offset(23, 41), paint);
        for (final y in [12.0, 20.0, 28.0, 36.0]) {
          canvas.drawPath(
            Path()
              ..moveTo(15, y - 3)
              ..quadraticBezierTo(23, y + 4, 31, y - 3),
            paint,
          );
        }
      default:
        canvas.drawLine(const Offset(23, 42), const Offset(23, 26), paint);
        canvas.drawPath(
          Path()
            ..moveTo(23, 26)
            ..quadraticBezierTo(8, 22, 10, 12)
            ..quadraticBezierTo(16, 6, 23, 16)
            ..quadraticBezierTo(30, 6, 36, 12)
            ..quadraticBezierTo(38, 22, 23, 26),
          paint,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LeafPainter old) =>
      old.id != id || old.moss != moss;
}

class _ConePainter extends CustomPainter {
  final String id;
  final Color moss;

  _ConePainter(this.id, this.moss);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 46, size.height / 46);
    final paint = Paint()
      ..color = moss
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (id) {
      case '1':
        canvas.drawPath(
          Path()
            ..moveTo(23, 4)
            ..lineTo(31, 40)
            ..lineTo(15, 40)
            ..close(),
          paint,
        );
        canvas.drawLine(const Offset(18, 16), const Offset(28, 16), paint);
        canvas.drawLine(const Offset(17, 24), const Offset(29, 24), paint);
        canvas.drawLine(const Offset(16, 32), const Offset(30, 32), paint);
      case '2':
        canvas.drawCircle(const Offset(23, 18), 10, paint);
        canvas.drawLine(const Offset(23, 28), const Offset(23, 40), paint);
        canvas.drawLine(const Offset(16, 18), const Offset(30, 18), paint);
      default:
        canvas.drawCircle(const Offset(23, 16), 9, paint);
        canvas.drawPath(
          Path()
            ..moveTo(12, 22)
            ..quadraticBezierTo(23, 34, 34, 22),
          paint,
        );
        canvas.drawLine(const Offset(23, 30), const Offset(23, 40), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ConePainter old) =>
      old.id != id || old.moss != moss;
}
