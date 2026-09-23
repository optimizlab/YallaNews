// lib/widgets/custom_logo.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class YallaNewsLogo extends StatelessWidget {
  final double size;
  final Color? color;

  const YallaNewsLogo({Key? key, this.size = 24, this.color}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final assetPath = 'assets/img/yallanews_logo_2.svg';
    final effectiveColor = color ?? Theme.of(context).colorScheme.onSurface;
    return SvgPicture.asset(
      assetPath,
      height: size,
      color: effectiveColor,
    );
  }
}
