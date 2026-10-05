import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A premium container that replaces the standard Card for a more professional look.
/// It uses a subtle shadow and hairline border to create depth without looking bulky.
class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;

  const PremiumCard({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppPalette.card,
        borderRadius: BorderRadius.circular(20),
        border: const BorderSide(color: AppPalette.hairline, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppPalette.ink.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
