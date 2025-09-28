import 'package:flutter/material.dart';

class BrandHeader extends StatelessWidget {
  final bool centered;
  final double size;

  const BrandHeader({
    super.key,
    this.centered = true,
    this.size = 120, // tamaño por defecto
  });

  @override
  Widget build(BuildContext context) {
    final widget = Image.asset(
      'lib/assets/AlertaVital.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );

    return centered ? Center(child: widget) : widget;
  }
}
