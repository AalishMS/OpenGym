import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class StepperWidget extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final double step;
  final Color accent;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color borderColor;
  final Color textPrimaryColor;
  final Color textSecondaryColor;
  final void Function(double) onChanged;

  const StepperWidget({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.accent,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.borderColor,
    required this.textPrimaryColor,
    required this.textSecondaryColor,
    required this.onChanged,
  });

  @override
  State<StepperWidget> createState() => _StepperWidgetState();
}

class _StepperWidgetState extends State<StepperWidget> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isEditing = false;
  double _currentValue = 0;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
    _controller = TextEditingController(text: _formatValue(widget.value));
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _commitValue();
    });
  }

  @override
  void didUpdateWidget(StepperWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _currentValue) {
      _currentValue = widget.value;
      _controller.text = _formatValue(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _formatValue(double val) {
    return val == val.roundToDouble() ? '${val.toInt()}' : val.toString();
  }

  void _commitValue() {
    final text = _controller.text.trim();
    final parsed = double.tryParse(text);
    if (parsed == null || text.isEmpty) {
      _currentValue = widget.min;
    } else {
      _currentValue = parsed.clamp(widget.min, widget.max);
    }
    _controller.text = _formatValue(_currentValue);
    widget.onChanged(_currentValue);
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              border: Border(
                top: BorderSide(color: widget.borderColor),
                bottom: BorderSide(color: widget.borderColor),
              ),
            ),
            child: SizedBox(
              width: 30,
              height: 24,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _commitValue(),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  color: widget.textPrimaryColor,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => widget.onChanged((_currentValue - widget.step).clamp(widget.min, widget.max)),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: widget.surfaceColor,
              border: Border.all(color: widget.borderColor),
            ),
            child: Center(
              child: Text('−',
                  style: TextStyle(fontSize: 16, color: widget.textSecondaryColor)),
            ),
          ),
        ),
        GestureDetector(
          onTap: () {
            setState(() => _isEditing = true);
            _focusNode.requestFocus();
          },
          child: Container(
            width: 38,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              border: Border(
                top: BorderSide(color: widget.borderColor),
                bottom: BorderSide(color: widget.borderColor),
              ),
            ),
            child: Text(
              _formatValue(_currentValue),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                color: widget.textPrimaryColor,
              ),
            ),
          ),
        ),
        InkWell(
          onTap: () => widget.onChanged(_currentValue + widget.step),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: widget.surfaceColor,
              border: Border.all(color: widget.borderColor),
            ),
            child: Center(
              child: Text('+',
                  style: TextStyle(fontSize: 16, color: widget.accent)),
            ),
          ),
        ),
      ],
    );
  }
}
