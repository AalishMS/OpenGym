import 'package:flutter/material.dart';

enum NumericValueType { integer, decimal }

/// A numeric [TextField] with the keyboard and first-edit behavior shared by
/// workout and plan entry flows.
///
/// [TextField.selectAllOnFocus] selects the existing value once when focus is
/// acquired. Subsequent taps keep normal cursor/selection editing until the
/// field loses focus and is entered again.
class NumericTextField extends StatefulWidget {
  final TextEditingController controller;
  final NumericValueType valueType;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final bool autofocus;
  final TextAlign textAlign;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final TextStyle? style;

  const NumericTextField({
    super.key,
    required this.controller,
    required this.valueType,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.autofocus = false,
    this.textAlign = TextAlign.start,
    this.textInputAction,
    this.onSubmitted,
    this.style,
  });

  @override
  State<NumericTextField> createState() => _NumericTextFieldState();
}

class _NumericTextFieldState extends State<NumericTextField> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;

  @override
  void initState() {
    super.initState();
    _attachFocusNode(widget.focusNode);
  }

  @override
  void didUpdateWidget(NumericTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _detachFocusNode();
      _attachFocusNode(widget.focusNode);
    }
  }

  void _attachFocusNode(FocusNode? suppliedNode) {
    _ownsFocusNode = suppliedNode == null;
    _focusNode = suppliedNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  void _detachFocusNode() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) _focusNode.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) return;
      widget.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _detachFocusNode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      selectAllOnFocus: true,
      keyboardType: TextInputType.numberWithOptions(
        decimal: widget.valueType == NumericValueType.decimal,
      ),
      textAlign: widget.textAlign,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      style: widget.style,
      decoration: widget.decoration,
    );
  }
}
