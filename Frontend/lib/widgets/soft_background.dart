import 'package:flutter/material.dart';
import '../theme/brand_colors.dart';

class SoftBackground extends StatelessWidget {
  const SoftBackground({super.key});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SoftBgPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _SoftBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [BrandColors.surface, BrandColors.surfaceAlt],
    ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..shader = gradient);

    final coral = Paint()..color = BrandColors.secondary.withOpacity(.10);
    final purple = Paint()..color = BrandColors.primary.withOpacity(.10);

    canvas.drawCircle(Offset(size.width * .2, size.height * .18), 120, purple);
    canvas.drawCircle(Offset(size.width * .85, size.height * .80), 140, coral);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
