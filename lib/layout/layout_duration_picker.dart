import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<int?> showLayoutDurationPicker(BuildContext context, int current) =>
    showDialog<int>(
      context: context,
      builder: (_) => _DurationDialog(current: current),
    );

class _DurationDialog extends StatefulWidget {
  const _DurationDialog({required this.current});
  final int current;
  @override
  State<_DurationDialog> createState() => _DurationDialogState();
}

class _DurationDialogState extends State<_DurationDialog> {
  late final _controller = TextEditingController(text: '${widget.current}');
  final _form = GlobalKey<FormState>();
  void _save() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, int.parse(_controller.text));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Recording duration'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Applies to every new video cell. Recording stops automatically. Existing clips stay unchanged.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final seconds in [3, 5, 7])
                  ActionChip(
                    label: Text('${seconds}s'),
                    onPressed: () => Navigator.pop(context, seconds),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('layout-custom-duration'),
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Custom duration (seconds)',
                helperText: '1–300 seconds',
              ),
              validator: (value) {
                final seconds = int.tryParse(value ?? '');
                return seconds == null || seconds < 1 || seconds > 300
                    ? 'Enter 1–300 seconds'
                    : null;
              },
              onFieldSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Set duration')),
    ],
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
