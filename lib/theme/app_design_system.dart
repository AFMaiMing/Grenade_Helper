import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// 响应式断点与移动端底部栏安全留白工具。
abstract final class AppBreakpoints {
  static const double mobile = 720;
  static const double expandedNavigation = 1280;
  static const double mobileBottomBarHeight = 70;
  static const double mobileBottomBarMinimumSafeArea = 10;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobile;

  static bool isExpandedNavigation(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= expandedNavigation;

  /// 为透明移动端底部栏预留底部滚动留白。
  static EdgeInsets withMobileBottomBarClearance(
    BuildContext context,
    EdgeInsets padding,
  ) {
    final systemBottomInset = MediaQuery.paddingOf(context).bottom;
    const minimumClearance =
        mobileBottomBarHeight + mobileBottomBarMinimumSafeArea;
    final bottomBarClearance = systemBottomInset > minimumClearance
        ? systemBottomInset
        : minimumClearance;
    return EdgeInsets.fromLTRB(
      padding.left,
      padding.top,
      padding.right,
      padding.bottom + bottomBarClearance,
    );
  }
}

/// 全局统一动效时长与曲线常量。
abstract final class AppMotion {
  static const Duration quick = Duration(milliseconds: 150);
  static const Duration content = Duration(milliseconds: 220);
  static const Duration panel = Duration(milliseconds: 300);
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
}

/// 应用语义化扩展色板，覆盖表面层级与道具类型色值。
@immutable
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  final Color canvas;
  final Color raisedSurface;
  final Color subtleBorder;
  final Color mutedText;
  final Color smoke;
  final Color flash;
  final Color molotov;
  final Color he;
  final Color wallbang;

  const AppThemeExtension({
    required this.canvas,
    required this.raisedSurface,
    required this.subtleBorder,
    required this.mutedText,
    required this.smoke,
    required this.flash,
    required this.molotov,
    required this.he,
    required this.wallbang,
  });

  static const light = AppThemeExtension(
    canvas: Color(0xFFF4F5F6),
    raisedSurface: Color(0xFFFFFFFF),
    subtleBorder: Color(0xFFE0E3E6),
    mutedText: Color(0xFF6F767E),
    smoke: Color(0xFF64727D),
    flash: Color(0xFFC39A00),
    molotov: Color(0xFFC53A2D),
    he: Color(0xFF258A49),
    wallbang: Color(0xFF007D91),
  );

  static const dark = AppThemeExtension(
    canvas: Color(0xFF0D0F12),
    raisedSurface: Color(0xFF22262B),
    subtleBorder: Color(0xFF30353B),
    mutedText: Color(0xFF9CA3AB),
    smoke: Color(0xFF9CA8B1),
    flash: Color(0xFFFFD84A),
    molotov: Color(0xFFFF6B57),
    he: Color(0xFF62D480),
    wallbang: Color(0xFF4DD5E7),
  );

  @override
  AppThemeExtension copyWith({
    Color? canvas,
    Color? raisedSurface,
    Color? subtleBorder,
    Color? mutedText,
    Color? smoke,
    Color? flash,
    Color? molotov,
    Color? he,
    Color? wallbang,
  }) {
    return AppThemeExtension(
      canvas: canvas ?? this.canvas,
      raisedSurface: raisedSurface ?? this.raisedSurface,
      subtleBorder: subtleBorder ?? this.subtleBorder,
      mutedText: mutedText ?? this.mutedText,
      smoke: smoke ?? this.smoke,
      flash: flash ?? this.flash,
      molotov: molotov ?? this.molotov,
      he: he ?? this.he,
      wallbang: wallbang ?? this.wallbang,
    );
  }

  @override
  AppThemeExtension lerp(AppThemeExtension? other, double t) {
    if (other == null) return this;
    return AppThemeExtension(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      raisedSurface: Color.lerp(raisedSurface, other.raisedSurface, t)!,
      subtleBorder: Color.lerp(subtleBorder, other.subtleBorder, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      smoke: Color.lerp(smoke, other.smoke, t)!,
      flash: Color.lerp(flash, other.flash, t)!,
      molotov: Color.lerp(molotov, other.molotov, t)!,
      he: Color.lerp(he, other.he, t)!,
      wallbang: Color.lerp(wallbang, other.wallbang, t)!,
    );
  }
}

/// 便捷读取当前上下文对应的扩展主题色板。
extension AppThemeContext on BuildContext {
  AppThemeExtension get appTheme {
    final theme = Theme.of(this);
    return theme.extension<AppThemeExtension>() ??
        (theme.brightness == Brightness.dark
            ? AppThemeExtension.dark
            : AppThemeExtension.light);
  }
}

/// 亮色与暗色全局 Material 3 主题构建入口。
abstract final class AppTheme {
  static const BorderRadius _defaultRadius =
      BorderRadius.all(Radius.circular(8));
  static const RoundedRectangleBorder _defaultShape =
      RoundedRectangleBorder(borderRadius: _defaultRadius);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final extension = isDark ? AppThemeExtension.dark : AppThemeExtension.light;
    final seedColor =
        isDark ? const Color(0xFFFFB44C) : const Color(0xFFC65D00);
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      primary: seedColor,
      surface: isDark ? const Color(0xFF171A1E) : Colors.white,
    );
    final textColor =
        isDark ? const Color(0xFFF2F3F4) : const Color(0xFF171A1D);
    final subtleSide = BorderSide(color: extension.subtleBorder);
    final defaultInputBorder = OutlineInputBorder(
      borderRadius: _defaultRadius,
      borderSide: subtleSide,
    );
    final indicatorColor = scheme.primary.withValues(alpha: 0.14);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: extension.canvas,
      canvasColor: extension.canvas,
      dividerColor: extension.subtleBorder,
      extensions: [extension],
      visualDensity: VisualDensity.standard,
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
            bodyColor: textColor,
            displayColor: textColor,
          ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: extension.canvas,
        foregroundColor: textColor,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: textColor,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: subtleSide,
          borderRadius: _defaultRadius,
        ),
      ),
      dividerTheme: DividerThemeData(color: extension.subtleBorder, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: extension.raisedSurface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: defaultInputBorder,
        enabledBorder: defaultInputBorder,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 44),
          shape: _defaultShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 44),
          shape: _defaultShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      chipTheme: ChipThemeData(
        shape: _defaultShape,
        side: subtleSide,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: _defaultShape,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: indicatorColor,
        indicatorShape: _defaultShape,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: indicatorColor,
        indicatorShape: _defaultShape,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}
