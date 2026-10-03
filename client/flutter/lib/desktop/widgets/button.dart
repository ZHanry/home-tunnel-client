import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';

class Button extends StatefulWidget {
  final GestureTapCallback onTap;
  final String text;
  final double? textSize;
  final double? minWidth;
  final bool isOutline;
  final double? padding;
  final Color? textColor;
  final double? radius;
  final Color? borderColor;

  Button({
    Key? key,
    this.minWidth,
    this.isOutline = false,
    this.textSize,
    this.padding,
    this.textColor,
    this.radius,
    this.borderColor,
    required this.onTap,
    required this.text,
  }) : super(key: key);

  @override
  State<Button> createState() => _ButtonState();
}

class _ButtonState extends State<Button> {
  RxBool hover = false.obs;
  RxBool pressed = false.obs;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme; // HOMEDESK: 统一按钮配色

    return Obx(() => InkWell(
          onTapDown: (_) => pressed.value = true,
          onTapUp: (_) => pressed.value = false,
          onTapCancel: () => pressed.value = false,
          onHover: (value) => hover.value = value,
          onTap: widget.onTap,
          child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: widget.minWidth ?? 70.0,
              ),
              child: Container(
                padding: EdgeInsets.all(widget.padding ?? 4.5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: pressed.value
                      ? colors.primary
                      : (widget.isOutline
                          ? Colors.transparent
                          : colors.primary),
                  border: Border.all(
                    color: pressed.value
                        ? colors.primary
                        : hover.value
                            ? colors.primary
                            : (widget.isOutline
                                ? widget.borderColor ?? colors.outlineVariant
                                : colors.primary),
                  ),
                  borderRadius: BorderRadius.circular(widget.radius ?? 11),
                ),
                child: Text(
                  translate(
                    widget.text,
                  ),
                  style: TextStyle(
                      fontSize: widget.textSize ?? 12.0,
                      color: widget.isOutline
                          ? widget.textColor ??
                              Theme.of(context).textTheme.titleLarge?.color
                          : colors.onPrimary),
                ).marginSymmetric(horizontal: 12),
              )),
        ));
  }
}

class FixedWidthButton extends StatefulWidget {
  final GestureTapCallback onTap;
  final String text;
  final double? textSize;
  final double width;
  final bool isOutline;
  final double? padding;
  final Color? textColor;
  final double? radius;
  final Color? borderColor;
  final int? maxLines;

  FixedWidthButton({
    Key? key,
    required this.width,
    this.maxLines,
    this.isOutline = false,
    this.textSize,
    this.padding,
    this.textColor,
    this.radius,
    this.borderColor,
    required this.onTap,
    required this.text,
  }) : super(key: key);

  @override
  State<FixedWidthButton> createState() => _FixedWidthButtonState();
}

class _FixedWidthButtonState extends State<FixedWidthButton> {
  RxBool hover = false.obs;
  RxBool pressed = false.obs;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme; // HOMEDESK: 统一按钮配色

    return Obx(() => InkWell(
          onTapDown: (_) => pressed.value = true,
          onTapUp: (_) => pressed.value = false,
          onTapCancel: () => pressed.value = false,
          onHover: (value) => hover.value = value,
          onTap: widget.onTap,
          child: Container(
            width: widget.width,
            padding: EdgeInsets.all(widget.padding ?? 4.5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: pressed.value
                  ? colors.primary
                  : (widget.isOutline ? Colors.transparent : colors.primary),
              border: Border.all(
                color: pressed.value
                    ? colors.primary
                    : hover.value
                        ? colors.primary
                        : (widget.isOutline
                            ? widget.borderColor ?? colors.outlineVariant
                            : colors.primary),
              ),
              borderRadius: BorderRadius.circular(widget.radius ?? 11),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: AutoSizeText(
                    translate(
                      widget.text,
                    ),
                    maxLines: widget.maxLines ?? 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: widget.textSize ?? 12.0,
                        color: widget.isOutline
                            ? widget.textColor ??
                                Theme.of(context).textTheme.titleLarge?.color
                            : colors.onPrimary),
                  ).marginSymmetric(horizontal: 12),
                ),
              ],
            ),
          ),
        ));
  }
}
