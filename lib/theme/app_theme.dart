import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the premium look.
///
/// Palette: cool mist background, deep forest green primary, a single muted
/// gold reserved strictly for money figures. Type: Manrope for UI, Fraunces
/// (italic serif) for the wordmark and every rupee amount — the one
/// memorable accent in an otherwise quiet, financial tone.
class AppPalette {
  AppPalette._();

  static const mist = Color(0xFFF3F6F2); // app background (cool, not cream)
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF17251E); // primary text
  static const muted = Color(0xFF5F6E64); // secondary text
  static const forest = Color(0xFF1B4332); // primary
  static const forestDeep = Color(0xFF0D2B1F);
  static const moss = Color(0xFF2D6A4F); // secondary
  static const mint = Color(0xFFD9E9DF); // primary container
  static const mintDeep = Color(0xFF0A2623);
  static const gold = Color(0xFFA87C1E); // money accent
  static const goldSoft = Color(0xFFF4EAD2); // money tint background
  static const hairline = Color(0xFFE4EBE3);
  static const good = Color(0xFF2E7D5B);
  static const bad = Color(0xFFB3261E);
}

/// Serif money figure — the signature premium touch.
class MoneyText extends StatelessWidget {
  const MoneyText(this.text, {super.key, this.size = 16, required this.color});

  final String text;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.fraunces(
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w600,
        fontSize: size,
        color: color,
        height: 1.1,
      ),
    );
  }
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.light(
    primary: AppPalette.forest,
    onPrimary: Colors.white,
    primaryContainer: AppPalette.mint,
    onPrimaryContainer: AppPalette.mintDeep,
    secondary: AppPalette.moss,
    onSecondary: Colors.white,
    secondaryContainer: AppPalette.mint,
    onSecondaryContainer: AppPalette.mintDeep,
    tertiary: AppPalette.gold,
    onTertiary: Colors.white,
    tertiaryContainer: AppPalette.goldSoft,
    onTertiaryContainer: Color(0xFF3D2E0C),
    error: AppPalette.bad,
    onError: Colors.white,
    errorContainer: Color(0xFFF7DAD8),
    onErrorContainer: Color(0xFF4A1210),
    surface: AppPalette.card,
    onSurface: AppPalette.ink,
    onSurfaceVariant: AppPalette.muted,
    outline: AppPalette.muted,
    outlineVariant: AppPalette.hairline,
    surfaceContainerHighest: Color(0xFFE9EFE8),
    surfaceContainerLow: Color(0xFFEDF1EC),
    surfaceContainer: Color(0xFFE7EDE6),
    surfaceContainerHigh: Color(0xFFE2E8E1),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    inverseSurface: AppPalette.forestDeep,
    onInverseSurface: Color(0xFFEDF3EE),
    inversePrimary: Color(0xFFA9D4BD),
    shadow: AppPalette.ink,
    scrim: Color(0x8022382C),
    surfaceTint: AppPalette.forest,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final textTheme = GoogleFonts.manropeTextTheme(base.textTheme).apply(
    bodyColor: AppPalette.ink,
    displayColor: AppPalette.ink,
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppPalette.mist,
    colorScheme: scheme,
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        color: AppPalette.ink,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppPalette.card,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppPalette.hairline, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF0F4EF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      labelStyle: GoogleFonts.manrope(
        color: AppPalette.muted,
        fontSize: 14,
      ),
      hintStyle: GoogleFonts.manrope(color: AppPalette.muted, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE3E9E2), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppPalette.forest, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppPalette.forest,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: GoogleFonts.manrope(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: AppPalette.card,
        foregroundColor: AppPalette.forest,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        side: const BorderSide(color: AppPalette.hairline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: GoogleFonts.manrope(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppPalette.forest,
        textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppPalette.gold,
      foregroundColor: AppPalette.forestDeep,
      elevation: 8,
      focusElevation: 8,
      hoverElevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
      sizeConstraints: BoxConstraints.tightFor(width: 60, height: 60),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppPalette.ink,
      contentTextStyle: GoogleFonts.manrope(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 6,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppPalette.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      titleTextStyle: GoogleFonts.manrope(
        fontSize: 19,
        fontWeight: FontWeight.w800,
        color: AppPalette.ink,
      ),
      contentTextStyle: GoogleFonts.manrope(fontSize: 14, color: AppPalette.muted),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppPalette.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: AppPalette.hairline,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppPalette.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: AppPalette.mint,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppPalette.forest
              : AppPalette.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? AppPalette.forest
              : AppPalette.muted,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFFEFF4EF),
      side: const BorderSide(color: AppPalette.hairline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelStyle: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600),
      secondaryLabelStyle:
          GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    ),
    dividerTheme: const DividerThemeData(color: AppPalette.hairline, thickness: 1),
    listTileTheme: const ListTileThemeData(),
    popupMenuTheme: PopupMenuThemeData(
      color: AppPalette.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: GoogleFonts.manrope(fontSize: 14),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppPalette.ink,
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: GoogleFonts.manrope(fontSize: 12, color: Colors.white),
      waitDuration: const Duration(milliseconds: 400),
    ),
  );
}