import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Deterministic soft-gradient monogram for a group, so each group gets a
/// stable but slightly different avatar color.
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({super.key, required this.name, required this.size});

  final String name;
  final double size;

  static const _pairs = <List<Color>>[
    [AppPalette.forest, AppPalette.moss],
    [Color(0xFF1B4B4A), Color(0xFF3E8E85)],
    [Color(0xFF7A5A15), AppPalette.gold],
    [Color(0xFF4A3E78), Color(0xFF7C6BB0)],
    [Color(0xFF773A2A), Color(0xFFB56B4F)],
  ];

  @override
  Widget build(BuildContext context) {
    final pair = _pairs[name.hashCode.abs() % _pairs.length];
    final letter = name.isEmpty ? '?' : name[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pair,
        ),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: Text(
        letter,
        style: GoogleFonts.manrope(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}