import 'package:flutter/material.dart';

/// An [AlertDialog] with a single text field that owns its controller.
///
/// Creating a [TextEditingController] next to `showDialog` and disposing it
/// after the await crashes: the future completes on `pop`, but the route keeps
/// rebuilding through its exit animation and the field would use a disposed
/// controller. Tying the controller to a [State] hands its lifetime to the
/// route.
///
/// Pops the trimmed text, or null when it was cancelled.
class TextInputDialog extends StatefulWidget {
  const TextInputDialog({
    required this.title,
    required this.confirmLabel,
    this.initialText = '',
    this.hintText,
    this.suffixText,
    this.helper,
    this.keyboardType,
    this.minLines = 1,
    this.maxLines = 1,
    this.monospace = false,
    this.validator,
    super.key,
  });

  final String title;
  final String confirmLabel;
  final String initialText;
  final String? hintText;
  final String? suffixText;

  /// Shown above the field, e.g. the code a year is being entered for.
  final Widget? helper;

  final TextInputType? keyboardType;
  final int minLines;
  final int maxLines;
  final bool monospace;

  /// Returns an error message to keep the dialog open, or null to accept.
  final String? Function(String value)? validator;

  @override
  State<TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<TextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    final error = widget.validator?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final singleLine = widget.maxLines == 1;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.helper != null) ...[
              widget.helper!,
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: widget.keyboardType,
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              style: widget.monospace
                  ? const TextStyle(fontFamily: 'monospace', fontSize: 12)
                  : null,
              decoration: InputDecoration(
                hintText: widget.hintText,
                suffixText: widget.suffixText,
                errorText: _error,
              ),
              onSubmitted: singleLine ? (_) => _submit() : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
