import 'package:flutter/material.dart';
import 'app_config.dart';

/// Spacing scale (logical pixels). Use these instead of ad-hoc values so
/// screens share one rhythm.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii.
abstract final class AppRadius {
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
}

/// Layout breakpoints, by available width.
///
/// * compact  (< 600): phones — navigation drawer, single column.
/// * medium   (600–1023): tablets — collapsed navigation rail.
/// * expanded (≥ 1024): desktops — full sidebar (collapsible).
abstract final class AppBreakpoints {
  static const double medium = 600;
  static const double expanded = 1024;

  static bool isCompact(double width) => width < medium;
  static bool isExpanded(double width) => width >= expanded;
}

/// App theme for the Legal Services admin panel.
///
/// The brand navy is kept as the primary color. Status colors were darkened
/// so text and icons using them meet WCAG AA contrast (≥ 4.5:1) on white.
class AppTheme {
  // Brand
  static const Color primary = Color(AppConfig.primaryColorValue); // #002366
  static const Color primaryDark = Color(0xFF001A4D);
  static const Color secondary = Color(0xFF1D5FBF); // interactive blue
  static const Color accent = Color(0xFFA16207); // legal gold (text-safe)
  static const Color gold = Color(0xFFD4A537); // decorative gold (logo)

  // Status (text-safe on white)
  static const Color danger = Color(0xFFB42318);
  static const Color success = Color(0xFF067647);
  static const Color warning = Color(0xFFB54708);
  static const Color info = Color(0xFF1D5FBF);

  // Neutrals
  static const Color background = Color(0xFFF5F7FA);
  static const Color surface = Colors.white;
  static const Color surfaceMuted = Color(0xFFF8FAFC);
  static const Color border = Color(0xFFE4E7EC);
  static const Color borderStrong = Color(0xFFD0D5DD);
  static const Color textPrimary = Color(0xFF101828);
  static const Color textSecondary = Color(0xFF475467);
  static const Color textMuted = Color(0xFF667085);

  // Navigation
  static const Color sidebar = Color(0xFF0B1F45);
  static const Color sidebarHover = Color(0x14FFFFFF);
  static const Color sidebarActive = Color(0x24FFFFFF);
  static const Color sidebarText = Color(0xFFC9D2E3);

  /// Filled red style for the confirming action of destructive dialogs
  /// (delete, cancel subscription). Applied to the existing TextButtons.
  static final ButtonStyle destructiveButtonStyle = TextButton.styleFrom(
    backgroundColor: danger,
    foregroundColor: Colors.white,
    disabledBackgroundColor: const Color(0xFFEAECF0),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    minimumSize: const Size(64, 44),
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
  ).copyWith(
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) return Colors.white.withValues(alpha: 0.16);
      if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
        return Colors.white.withValues(alpha: 0.10);
      }
      return null;
    }),
  );

  /// Soft tinted background for a status color (chips, icon tiles).
  static Color tint(Color color, [double alpha = 0.10]) =>
      color.withValues(alpha: alpha);

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE6ECF7),
      onPrimaryContainer: primary,
      secondary: secondary,
      onSecondary: Colors.white,
      tertiary: accent,
      error: danger,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: surfaceMuted,
      surfaceContainer: const Color(0xFFF2F4F7),
      surfaceContainerHigh: const Color(0xFFEAECF0),
      surfaceContainerHighest: const Color(0xFFE4E7EC),
      outline: borderStrong,
      outlineVariant: border,
      surfaceTint: Colors.transparent,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);
    final themed = base.textTheme
        .copyWith(
          headlineMedium: base.textTheme.headlineMedium!.copyWith(fontSize: 26, fontWeight: FontWeight.w700, height: 1.25, letterSpacing: -0.2),
          headlineSmall: base.textTheme.headlineSmall!.copyWith(fontSize: 22, fontWeight: FontWeight.w700, height: 1.3, letterSpacing: -0.1),
          titleLarge: base.textTheme.titleLarge!.copyWith(fontSize: 18, fontWeight: FontWeight.w600, height: 1.35),
          titleMedium: base.textTheme.titleMedium!.copyWith(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4),
          titleSmall: base.textTheme.titleSmall!.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.4),
          bodyLarge: base.textTheme.bodyLarge!.copyWith(fontSize: 15, height: 1.5),
          bodyMedium: base.textTheme.bodyMedium!.copyWith(fontSize: 14, height: 1.45),
          bodySmall: base.textTheme.bodySmall!.copyWith(fontSize: 12.5, height: 1.4, color: textMuted),
          labelLarge: base.textTheme.labelLarge!.copyWith(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1),
          labelMedium: base.textTheme.labelMedium!.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.1),
          labelSmall: base.textTheme.labelSmall!.copyWith(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4),
        )
        .apply(bodyColor: textPrimary, displayColor: textPrimary);
    final text = themed.copyWith(bodySmall: themed.bodySmall!.copyWith(color: textMuted));
    final buttonText = text.labelLarge!;

    OutlineInputBorder outline(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: color, width: width),
        );

    const buttonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 12);
    const buttonShape = RoundedRectangleBorder(borderRadius: AppRadius.mdAll);
    const minButton = Size(64, 44);

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: text,
      visualDensity: VisualDensity.standard,
      dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
      iconTheme: const IconThemeData(color: textSecondary, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        shape: const Border(bottom: BorderSide(color: border)),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: border),
        ),
        margin: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 5),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xxs),
        titleTextStyle: text.titleSmall!.copyWith(color: textPrimary, fontSize: 14.5),
        subtitleTextStyle: text.bodySmall!.copyWith(color: textSecondary, fontSize: 13),
        iconColor: textSecondary,
        minVerticalPadding: AppSpacing.md,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hoverColor: surfaceMuted,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: text.bodyMedium!.copyWith(color: textSecondary),
        // Floating labels are drawn at 75 % scale, so 16 px renders at 12 px.
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
          final base = text.bodyLarge!.copyWith(fontSize: 16, fontWeight: FontWeight.w500);
          if (states.contains(WidgetState.error)) return base.copyWith(color: danger);
          if (states.contains(WidgetState.focused)) return base.copyWith(color: secondary);
          return base.copyWith(color: textSecondary);
        }),
        hintStyle: text.bodyMedium!.copyWith(color: textMuted),
        helperStyle: text.bodySmall,
        helperMaxLines: 3,
        errorStyle: text.bodySmall!.copyWith(color: danger, fontWeight: FontWeight.w500),
        errorMaxLines: 3,
        counterStyle: text.bodySmall,
        prefixIconColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.focused) ? secondary : textMuted,
        ),
        suffixIconColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.focused) ? secondary : textMuted,
        ),
        border: outline(borderStrong),
        enabledBorder: outline(borderStrong),
        focusedBorder: outline(secondary, 2),
        errorBorder: outline(danger),
        focusedErrorBorder: outline(danger, 2),
        disabledBorder: outline(border),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: text.bodyMedium,
        menuStyle: const MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surface),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: AppRadius.mdAll)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFEAECF0),
          disabledForegroundColor: textMuted,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: minButton,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: buttonText,
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return Colors.white.withValues(alpha: 0.16);
            if (states.contains(WidgetState.hovered)) return Colors.white.withValues(alpha: 0.08);
            if (states.contains(WidgetState.focused)) return Colors.white.withValues(alpha: 0.12);
            return null;
          }),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: minButton,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          backgroundColor: surface,
          minimumSize: minButton,
          padding: buttonPadding,
          side: const BorderSide(color: borderStrong),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: secondary,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textSecondary,
          minimumSize: const Size(40, 40),
          shape: buttonShape,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium!.copyWith(color: textSecondary),
        actionsPadding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, AppSpacing.xl),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: const BorderSide(color: border),
        ),
        textStyle: text.bodyMedium,
        labelTextStyle: WidgetStatePropertyAll(text.bodyMedium),
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surface),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: textPrimary, borderRadius: AppRadius.smAll),
        textStyle: text.bodySmall!.copyWith(color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 400),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textPrimary,
        contentTextStyle: text.bodyMedium!.copyWith(color: Colors.white),
        actionTextColor: const Color(0xFF9EC5FF),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        width: null,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: const Color(0xFFE6ECF7),
        labelStyle: text.labelMedium!.copyWith(color: textPrimary),
        side: const BorderSide(color: borderStrong),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: const WidgetStatePropertyAll(surfaceMuted),
        headingTextStyle: text.labelMedium!.copyWith(color: textSecondary, letterSpacing: 0.3),
        dataTextStyle: text.bodyMedium,
        headingRowHeight: 44,
        dataRowMinHeight: 56,
        dataRowMaxHeight: 64,
        horizontalMargin: AppSpacing.lg,
        columnSpacing: AppSpacing.xl,
        dividerThickness: 1,
        dataRowColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ? surfaceMuted : null,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
        side: const BorderSide(color: borderStrong, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : null,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : borderStrong,
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : const Color(0xFFEAECF0),
        ),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : borderStrong,
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: primary,
        thumbColor: primary,
        inactiveTrackColor: Color(0xFFEAECF0),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: secondary,
        linearTrackColor: Color(0xFFE6ECF7),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        headerBackgroundColor: primary,
        headerForegroundColor: Colors.white,
        dayShape: const WidgetStatePropertyAll(CircleBorder()),
      ),
      timePickerTheme: const TimePickerThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: sidebar,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(),
        endShape: RoundedRectangleBorder(),
      ),
      scrollbarTheme: const ScrollbarThemeData(
        radius: Radius.circular(8),
        thickness: WidgetStatePropertyAll(6),
      ),
    );
  }
}
