import 'package:flutter/material.dart';

/// Semantic surface + ink tokens.
///
/// Nothing in the UI names a raw hex value; it reads a token off this
/// extension instead, so light and dark stay in lockstep by construction.
/// Hierarchy is carried by *opacity over ink*, never by a second hue —
/// the only chromatic colours in the app are [success] and [danger], and
/// they are reserved for the verdict.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color borderSubtle;

  /// The one "accent": near-black on paper, near-white on ink.
  final Color ink;

  /// Text/icon colour on top of a solid [ink] fill.
  final Color onInk;

  final Color success;
  final Color danger;

  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.borderSubtle,
    required this.ink,
    required this.onInk,
    required this.success,
    required this.danger,
  });

  // ── Opacity ladder ────────────────────────────────────────────────────────
  // The single mechanism for text hierarchy. Same four steps in both modes.
  Color get textPrimary => ink;
  Color get textSecondary => ink.withValues(alpha: 0.60);
  Color get textTertiary => ink.withValues(alpha: 0.40);
  Color get textGhost => ink.withValues(alpha: 0.26);

  static const light = AppPalette(
    background: Color(0xFFFAFAF9), // stone-50
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF5F5F4), // stone-100
    border: Color(0xFFE7E5E4), // stone-200
    borderSubtle: Color(0xFFEFEDEC),
    ink: Color(0xFF1C1917), // stone-900
    onInk: Color(0xFFFAFAF9),
    success: Color(0xFF1F7A4D),
    danger: Color(0xFFB42318),
  );

  static const dark = AppPalette(
    background: Color(0xFF0C0A09), // stone-950
    surface: Color(0xFF16130F),
    surfaceMuted: Color(0xFF1C1917), // stone-900
    border: Color(0xFF292524), // stone-800
    borderSubtle: Color(0xFF201C1A),
    ink: Color(0xFFFAFAF9), // stone-50
    onInk: Color(0xFF0C0A09),
    success: Color(0xFF6FC28F),
    danger: Color(0xFFE8857B),
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? border,
    Color? borderSubtle,
    Color? ink,
    Color? onInk,
    Color? success,
    Color? danger,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      ink: ink ?? this.ink,
      onInk: onInk ?? this.onInk,
      success: success ?? this.success,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      onInk: Color.lerp(onInk, other.onInk, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

extension PaletteOf on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

/// 8px base unit. Every gap in the app is one of these.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
  static const xxxl = 64.0;

  /// Horizontal page gutter.
  static const gutter = 24.0;
}

abstract final class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 999.0;
}

/// One place for every duration and curve, so motion feels like one system.
abstract final class Motion {
  static const fast = Duration(milliseconds: 180);
  static const base = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 560);
  static const page = Duration(milliseconds: 420);

  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const standard = Curves.easeInOutCubic;
}

abstract final class AppTheme {
  static const _fontFamily = 'Inter';

  /// Digits that line up in a column — used for counters and metrics.
  static const tabular = <FontFeature>[FontFeature.tabularFigures()];

  static ThemeData light() => _build(Brightness.light, AppPalette.light);
  static ThemeData dark() => _build(Brightness.dark, AppPalette.dark);

  static ThemeData _build(Brightness brightness, AppPalette p) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: p.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: p.ink,
        brightness: brightness,
      ).copyWith(
        surface: p.background,
        onSurface: p.ink,
        primary: p.ink,
        onPrimary: p.onInk,
        outline: p.border,
        error: p.danger,
      ),
      extensions: [p],
      textTheme: _textTheme(p),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerTheme: DividerThemeData(
        color: p.border,
        thickness: 1,
        space: 1,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _FadeThroughTransitions(),
          TargetPlatform.iOS: _FadeThroughTransitions(),
        },
      ),
    );
  }

  /// Display sizes are *light* (300) with tight tracking; body is regular.
  /// Nothing in the app goes above 600 — weight is not how this UI shouts.
  static TextTheme _textTheme(AppPalette p) {
    return TextTheme(
      displaySmall: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 40,
        fontWeight: FontWeight.w300,
        height: 1.1,
        letterSpacing: -1.0,
        color: p.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 28,
        fontWeight: FontWeight.w300,
        height: 1.15,
        letterSpacing: -0.6,
        color: p.textPrimary,
      ),
      titleMedium: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.3,
        letterSpacing: -0.2,
        color: p.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.6,
        letterSpacing: -0.1,
        color: p.textSecondary,
      ),
      bodyMedium: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
        height: 1.55,
        color: p.textSecondary,
      ),
      // Uppercase micro-labels: the one place tracking opens up.
      labelSmall: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 10.5,
        fontWeight: FontWeight.w500,
        height: 1.2,
        letterSpacing: 1.3,
        color: p.textTertiary,
      ),
      labelMedium: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.3,
        letterSpacing: -0.1,
        color: p.textPrimary,
      ),
    );
  }
}

/// A quiet cross-fade with a few pixels of rise — no sliding panels.
class _FadeThroughTransitions extends PageTransitionsBuilder {
  const _FadeThroughTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Motion.enter);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.012),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// True when the platform asks for reduced motion. Ambient loops check this
/// and hold still; one-shot fades are cheap enough to keep either way.
bool reducedMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;
