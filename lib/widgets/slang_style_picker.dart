import 'package:flutter/material.dart';

import '../models/slang_style.dart';

/// The same explicit wording preference in settings and per-photo overrides.
class SlangStylePicker extends StatelessWidget {
  const SlangStylePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final SlangStyle value;
  final ValueChanged<SlangStyle>? onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<SlangStyle>(
    key: ValueKey(value),
    initialValue: value,
    isExpanded: true,
    decoration: const InputDecoration(
      labelText: 'Slang style',
      prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
    ),
    items: SlangStyle.values
        .map(
          (style) => DropdownMenuItem(value: style, child: Text(style.label)),
        )
        .toList(),
    onChanged: onChanged == null
        ? null
        : (style) {
            if (style != null) onChanged!(style);
          },
  );
}
