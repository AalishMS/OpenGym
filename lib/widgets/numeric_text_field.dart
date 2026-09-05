import 'package:flutter/material.dart';

enum NumericValueType { integer, decimal }

/// A numeric field with the correct mobile keyboard and select-all behavior
/// when focus is first acquired. Later taps retain normal cursor placement.
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
    _attach(widget.focusNode);
  }

  @override
  void didUpdateWidget(NumericTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _detach();
      _attach(widget.focusNode);
    }
  }

  void _attach(FocusNode? supplied) {
    _ownsFocusNode = supplied == null;
    _focusNode = supplied ?? FocusNode();
    _focusNode.addListener(_selectOnFocus);
  }

  void _detach() {
    _focusNode.removeListener(_selectOnFocus);
    if (_ownsFocusNode) _focusNode.dispose();
  }

  void _selectOnFocus() {
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
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
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
