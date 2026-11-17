import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

/// Opaque ink capsule (white label; inverted in dark mode) for actions that
/// belong to a card ("Open visit", "Retry upload"). Full width by default.
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Stretch to the available width.
  final bool expand;

  /// Shows a spinner and disables the button.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final enabled = onPressed != null && !loading;
    final button = FilledButton(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, AppTokens.primaryButtonHeight),
      ),
      child: _ButtonContent(
        label: label,
        icon: icon,
        loading: loading,
        spinnerColor: colors.muted,
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Light-grey capsule with an ink label for secondary actions ("Review
/// change", "All 24 delivered"). Full width by default.
class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
    this.large = true,
    this.loading = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  /// Error-coloured label and icon on the same grey capsule, for the one
  /// destructive action in a group (its confirmation dialog stays red).
  final bool destructive;

  /// 50 pt tall when true, 44 pt otherwise (inline "Stop", "Edit").
  final bool large;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final enabled = onPressed != null && !loading;
    final button = TextButton(
      onPressed: enabled ? onPressed : null,
      style: TextButton.styleFrom(
        minimumSize: Size(44,
            large ? AppTokens.primaryButtonHeight : AppTokens.minTouchTarget),
        foregroundColor: destructive ? colors.error : null,
        disabledForegroundColor:
            destructive ? colors.error.withValues(alpha: 0.4) : null,
      ),
      child: _ButtonContent(
        label: label,
        icon: icon,
        loading: loading,
        spinnerColor: destructive ? colors.error : colors.ink,
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Error-red fill for the confirm button of a destructive dialog ("Delete",
/// "Sign out"). Use only in confirmations; pair with a grey Cancel.
ButtonStyle appDestructiveButtonStyle(BuildContext context) {
  final colors = AppPalette.of(context);
  return FilledButton.styleFrom(
    backgroundColor: colors.error,
    foregroundColor: colors.onError,
  );
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.icon,
    required this.loading,
    required this.spinnerColor,
  });

  final String label;
  final IconData? icon;
  final bool loading;
  final Color spinnerColor;

  @override
  Widget build(BuildContext context) {
    final leading = loading
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2.2, color: spinnerColor),
          )
        : icon == null
            ? null
            : Icon(icon, size: 20);
    // A loose Flexible in a min-size row wraps the label within a bounded
    // width (large text on narrow screens) and stays on one line when the
    // width is unbounded (e.g. a non-expanded button in a Row).
    final Widget text =
        Flexible(child: Text(label, textAlign: TextAlign.center));
    if (leading == null) {
      return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [text]);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [leading, const SizedBox(width: 8), text],
    );
  }
}
