import 'package:flutter/material.dart';

class ShopLogo extends StatelessWidget {
  const ShopLogo({super.key});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: AspectRatio(
      aspectRatio: 3.2,
      child: Image.asset(
        'assets/logo.jpg',
        fit: BoxFit.cover,
        semanticLabel: 'Logo des Geschäfts',
        filterQuality: FilterQuality.medium,
      ),
    ),
  );
}
