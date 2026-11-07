import 'package:flutter/material.dart';

/// A themed [DropdownButtonFormField] that applies consistent styling
/// matching the app's design system.
///
/// Flutter 3.47.x does not expose a [ThemeData.dropdownTheme] for Material 2
/// [DropdownButton] widgets. The [dropdownMenuTheme] only affects Material 3's
/// [DropdownMenu], leaving [DropdownButtonFormField] menus with hardcoded
/// defaults (2px corner radius, [ColorScheme.canvasColor] background).
///
/// This widget wraps [DropdownButtonFormField] and applies:
/// - [borderRadius] defaulting to 12px rounded menu corners
/// - [dropdownColor] defaulting to [ColorScheme.surface] for menu background
/// - [iconEnabledColor] defaulting to [ColorScheme.primary] for the dropdown arrow
/// - [elevation] defaulting to 2 for menu shadow
///
/// All other parameters are passed through to [DropdownButtonFormField].
class AppDropdownButtonFormField<T> extends StatelessWidget {
  AppDropdownButtonFormField({
    super.key,
    required this.items,
    required this.onChanged,
    this.initialValue,
    this.hint,
    this.disabledHint,
    this.decoration,
    this.elevation = 2,
    this.style,
    this.icon,
    this.iconDisabledColor,
    this.iconEnabledColor,
    this.iconSize = 24.0,
    this.isDense = true,
    this.isExpanded = false,
    this.itemHeight,
    this.focusColor,
    this.focusNode,
    this.autofocus = false,
    this.dropdownColor,
    this.menuMaxHeight,
    this.enableFeedback,
    this.alignment = AlignmentDirectional.centerStart,
    this.borderRadius,
    this.padding,
    this.barrierDismissible = true,
    this.mouseCursor,
    this.dropdownMenuItemMouseCursor,
  }) : assert(
          items == null ||
              items.isEmpty ||
              initialValue == null ||
              items.where((item) => item.value == initialValue).length <= 1,
        );

  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final T? initialValue;
  final Widget? hint;
  final Widget? disabledHint;
  final InputDecoration? decoration;
  final int elevation;
  final TextStyle? style;
  final Widget? icon;
  final Color? iconDisabledColor;
  final Color? iconEnabledColor;
  final double iconSize;
  final bool isDense;
  final bool isExpanded;
  final double? itemHeight;
  final Color? focusColor;
  final FocusNode? focusNode;
  final bool autofocus;
  final Color? dropdownColor;
  final double? menuMaxHeight;
  final bool? enableFeedback;
  final AlignmentGeometry alignment;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool barrierDismissible;
  final MouseCursor? mouseCursor;
  final MouseCursor? dropdownMenuItemMouseCursor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DropdownButtonFormField<T>(
      key: key,
      items: items,
      onChanged: onChanged,
      initialValue: initialValue,
      hint: hint,
      disabledHint: disabledHint,
      decoration: decoration,
      elevation: elevation,
      style: style,
      icon: icon,
      iconDisabledColor: iconDisabledColor,
      iconEnabledColor: iconEnabledColor ?? colorScheme.primary,
      iconSize: iconSize,
      isDense: isDense,
      isExpanded: isExpanded,
      itemHeight: itemHeight,
      focusColor: focusColor,
      focusNode: focusNode,
      autofocus: autofocus,
      dropdownColor: dropdownColor ?? colorScheme.surface,
      menuMaxHeight: menuMaxHeight,
      enableFeedback: enableFeedback,
      alignment: alignment,
      borderRadius: borderRadius ?? BorderRadius.circular(12),
      padding: padding,
      barrierDismissible: barrierDismissible,
      mouseCursor: mouseCursor,
      dropdownMenuItemMouseCursor: dropdownMenuItemMouseCursor,
    );
  }
}