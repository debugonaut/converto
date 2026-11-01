import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/gui/output_names.dart';

class OutputNameField extends StatelessWidget {
  final TextEditingController controller;
  final String extension;
  final bool enabled;
  final bool numbered;
  final bool compact;
  final String? sourceLabel;
  const OutputNameField({
    super.key,
    required this.controller,
    required this.extension,
    this.enabled = true,
    this.numbered = false,
    this.compact = false,
    this.sourceLabel,
  });
  void _normalize() {
    try {
      final name = OutputNames.base(controller.text, extension: extension);
      if (controller.text != name)
        controller.value = TextEditingValue(
          text: name,
          selection: TextSelection.collapsed(offset: name.length),
        );
    } on ArgumentError {
      /* Inline validation explains the invalid name. */
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (focused) {
      if (!focused) _normalize();
    },
    child: TextField(
      controller: controller,
      enabled: enabled,
      autocorrect: false,
      onEditingComplete: () {
        _normalize();
        FocusScope.of(context).unfocus();
      },
      decoration: InputDecoration(
        labelText: sourceLabel == null
            ? 'Output name'
            : 'Output name · $sourceLabel',
        suffixText: '.$extension',
        errorText: OutputNames.fieldError(controller.text, extension),
        helperText: !compact && numbered
            ? 'Numbered files: ${_example()}'
            : null,
        helperMaxLines: 2,
        helperStyle: const TextStyle(color: AppTheme.muted, fontSize: 11),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: compact ? 10 : 14,
        ),
      ),
    ),
  );
  String _example() {
    try {
      return OutputNames.filename(controller.text, extension, index: 1);
    } catch (_) {
      return 'name_001.$extension';
    }
  }
}
