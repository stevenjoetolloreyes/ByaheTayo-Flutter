// iOS-style components for the Android app (Nov 7).
//
// Cupertino look, dark emerald colors, Inter + Plus Jakarta Sans fonts,
// Font Awesome icons (no SF Symbols, no San Francisco font — the SF
// family is Apple-platforms only and cannot be imported).
//
// SCOPE: appearance only. Same screens, same layout, same tap
// behaviour, same return values. The helpers below wrap Flutter's
// built-in Cupertino widgets and paint them in the app's emerald
// tokens (mirroring the preview tokens in main.dart: bg #0c1410,
// brand #16a34a, accent #34d399, cards #202B25).
//
// What lives here:
// - [iosCupertinoTheme] — the CupertinoThemeData the whole app uses
//   (wired in main.dart via MaterialApp.cupertinoOverrideTheme), so
//   every Cupertino widget renders in emerald + the app fonts.
// - [IosButton] — CupertinoButton in emerald (primary / secondary /
//   plain / destructive).
// - [IosSwitch] / [IosSwitchRow] — CupertinoSwitch, and the
//   SwitchListTile-shaped row around it (title + subtitle left,
//   switch right, row tap toggles).
// - [IosSegmentedControl] — CupertinoSegmentedControl, single-select
//   (all 12 SegmentedButton sites in the app are single-select).
// - [IosTextField] — CupertinoTextField in the dark card surface.
// - [showIosAlert] — CupertinoAlertDialog (simple title + message +
//   actions that only pop a value). Complex dialogs (forms, lists,
//   ChoiceChips) stay Material AlertDialog, restyled by the dialog
//   theme in main.dart.
// - [showIosSheet] — the app's modal bottom sheet with iOS chrome
//   (rounded top, drag handle, dark card). Same function, same
//   return values, same drag-to-dismiss as showModalBottomSheet —
//   only the chrome changes.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Emerald tokens — mirror the preview tokens in main.dart.
/// Never change these without changing main.dart too.
abstract final class IosColors {
  static const Color background = Color(0xFF0C1410);
  static const Color card = Color(0xFF202B25);
  static const Color elevated = Color(0xFF252B2D);
  static const Color brand = Color(0xFF16A34A);
  static const Color accent = Color(0xFF34D399);
  static const Color deepEmerald = Color(0xFF14532D);
  static const Color subtext = Color(0xFFB0B8B5);
  static const Color border = Color(0xFF343B3D);
  static const Color onDarkText = Color(0xFFFFFFFF);
  static const Color onLightText = Color(0xFF0F172A);

  /// iOS destructive red (Cupertino standard) for Delete actions.
  static const Color destructive = Color(0xFFFF3B30);
}

/// CupertinoThemeData for [brightness], in the app's emerald colors
/// and fonts. Cupertino widgets default to the SF Pro family, which
/// does not exist on Android — the textStyle below forces Inter so
/// the app font never changes.
CupertinoThemeData iosCupertinoTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return CupertinoThemeData(
    brightness: brightness,
    primaryColor: IosColors.brand,
    // White text on the emerald selected segment / primary button.
    primaryContrastingColor: Colors.white,
    scaffoldBackgroundColor:
        isDark ? IosColors.background : Colors.white,
    barBackgroundColor: isDark ? IosColors.card : Colors.white,
    // CupertinoThemeData has no plain textStyle — the font goes
    // through its textTheme. Cupertino widgets default to SF Pro,
    // which does not exist on Android, so Inter is forced here.
    textTheme: CupertinoTextThemeData(
      textStyle: TextStyle(
        fontFamily: 'Inter',
        color: isDark ? IosColors.onDarkText : IosColors.onLightText,
        fontSize: 16,
      ),
    ),
  );
}

/// iOS-style button (CupertinoButton) in emerald. Same 44pt minimum
/// tap height as iOS, pressed-opacity feedback instead of a ripple.
enum IosButtonStyle { primary, secondary, plain, destructive }

class IosButton extends StatelessWidget {
  const IosButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = IosButtonStyle.primary,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IosButtonStyle style;

  /// Optional leading icon (Font Awesome, like the rest of the app).
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final Color? background;
    final Color foreground;
    switch (style) {
      case IosButtonStyle.primary:
        background = IosColors.brand;
        foreground = Colors.white;
      case IosButtonStyle.secondary:
        background = IosColors.brand.withValues(alpha: 0.15);
        foreground = IosColors.accent;
      case IosButtonStyle.plain:
        background = null;
        foreground = IosColors.accent;
      case IosButtonStyle.destructive:
        background = IosColors.destructive;
        foreground = Colors.white;
    }
    final icon = this.icon;
    return CupertinoButton(
      color: background,
      borderRadius: BorderRadius.circular(12),
      pressedOpacity: 0.6,
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      onPressed: onPressed,
      child: icon == null
          ? Text(
              label,
              style: TextStyle(
                fontFamily: 'PlusJakartaSans',
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: foreground,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme.merge(
                  data: IconThemeData(color: foreground, size: 18),
                  child: icon,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'PlusJakartaSans',
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: foreground,
                  ),
                ),
              ],
            ),
    );
  }
}

/// iOS-style switch (CupertinoSwitch) in emerald.
class IosSwitch extends StatelessWidget {
  const IosSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return CupertinoSwitch(
      value: value,
      onChanged: onChanged,
      activeTrackColor: IosColors.brand,
      inactiveTrackColor:
          isDark ? IosColors.border : const Color(0xFFE2E8F0),
      thumbColor: Colors.white,
    );
  }
}

/// SwitchListTile-shaped row with an iOS switch: title + subtitle
/// on the left, [IosSwitch] on the right. Tapping the row toggles,
/// exactly like SwitchListTile. Drop-in for the three SwitchListTile
/// sites in the app.
class IosSwitchRow extends StatelessWidget {
  const IosSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.contentPadding =
        const EdgeInsets.symmetric(horizontal: 16),
  });

  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: contentPadding,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  title,
                  if (subtitle != null) subtitle,
                ],
              ),
            ),
            const SizedBox(width: 12),
            IosSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// One option for [IosSegmentedControl].
class IosSegment<T extends Object> {
  const IosSegment({required this.value, required this.label});
  final T value;
  final String label;
}

/// iOS-style segmented control (CupertinoSegmentedControl) in
/// emerald. Single-select only — every SegmentedButton in the app
/// is single-select, so the API mirrors that: one [groupValue],
/// one [onValueChanged]. Pass null [groupValue] for no selection
/// (the AI quiz custom-count case).
class IosSegmentedControl<T extends Object> extends StatelessWidget {
  const IosSegmentedControl({
    super.key,
    required this.segments,
    required this.groupValue,
    required this.onValueChanged,
  });

  final List<IosSegment<T>> segments;
  final T? groupValue;
  final ValueChanged<T> onValueChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: double.infinity,
      child: CupertinoSegmentedControl<T>(
        children: {
          for (final s in segments)
            s.value: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Text(s.label, textAlign: TextAlign.center),
            ),
        },
        groupValue: groupValue,
        onValueChanged: onValueChanged,
        selectedColor: IosColors.brand,
        unselectedColor: isDark ? IosColors.card : Colors.white,
        borderColor:
            isDark ? IosColors.border : const Color(0xFFE2E8F0),
        pressedColor: IosColors.brand.withValues(alpha: 0.35),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// iOS-style text field (CupertinoTextField) in the dark card
/// surface, emerald cursor. No underline, no focus ring — the iOS
/// field look. Form fields with validators/labels stay Material
/// TextFormField (restyled by the input decoration theme).
class IosTextField extends StatelessWidget {
  const IosTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.prefix,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.maxLines = 1,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final Widget? prefix;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final int maxLines;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return CupertinoTextField(
      controller: controller,
      focusNode: focusNode,
      placeholder: placeholder,
      prefix: prefix,
      suffix: suffix,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      maxLines: maxLines,
      enabled: enabled,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: TextStyle(
        fontFamily: 'Inter',
        color: isDark ? IosColors.onDarkText : IosColors.onLightText,
      ),
      placeholderStyle: const TextStyle(
        fontFamily: 'Inter',
        color: IosColors.subtext,
      ),
      decoration: BoxDecoration(
        color: isDark ? IosColors.card : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? IosColors.border : const Color(0xFFE2E8F0),
        ),
      ),
      cursorColor: IosColors.brand,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}

/// Single-action informational alert (Close). Pops null — the
/// iOS equivalent of the one-button Material AlertDialogs.
Future<void> showIosMessage({
  required BuildContext context,
  required String title,
  required String message,
  String actionLabel = 'Close',
}) {
  return showCupertinoDialog<void>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
}

/// One action for [showIosAlert]. [value] is what the dialog pops
/// when tapped (null pops null, like Navigator.pop with no value).
/// [isDefault] bolds the action (the primary choice); [isDestructive]
/// paints it iOS red (Delete).
class IosAlertAction<T> {
  const IosAlertAction(
    this.label, {
    this.value,
    this.isDefault = false,
    this.isDestructive = false,
  });

  final String label;
  final T? value;
  final bool isDefault;
  final bool isDestructive;
}

/// iOS-style alert (CupertinoAlertDialog): title + message + actions
/// that only pop a value. Same return contract as showDialog —
/// null when dismissed via the barrier. For dialogs with forms,
/// lists, or ChoiceChips, keep Material AlertDialog (restyled by
/// the dialog theme in main.dart).
Future<T?> showIosAlert<T>({
  required BuildContext context,
  required String title,
  required String message,
  required List<IosAlertAction<T>> actions,
  bool barrierDismissible = true,
}) {
  return showCupertinoDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        for (final a in actions)
          CupertinoDialogAction(
            isDefaultAction: a.isDefault,
            isDestructiveAction: a.isDestructive,
            onPressed: () => Navigator.of(context).pop(a.value),
            child: Text(a.label),
          ),
      ],
    ),
  );
}

/// The app's modal bottom sheet with iOS chrome: rounded top
/// corners, a drag handle, and the dark card surface. Same function,
/// same return values, same drag-to-dismiss as showModalBottomSheet
/// — only the chrome changes. [shape] overrides the iOS top radius
/// when a caller already sets one (the Fares breakdown sheet).
Future<T?> showIosSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  RoundedRectangleBorder? shape,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: isDark ? IosColors.card : Colors.white,
    shape: shape ??
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
    showDragHandle: true,
    barrierColor: Colors.black54,
    builder: builder,
  );
}
