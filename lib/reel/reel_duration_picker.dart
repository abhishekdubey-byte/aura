import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'reel_session.dart';

Future<int?> showReelDurationPicker(BuildContext context, int current) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DurationSheet(current: current),
    );

class _DurationSheet extends StatefulWidget {
  const _DurationSheet({required this.current});
  final int current;
  @override
  State<_DurationSheet> createState() => _DurationSheetState();
}

class _DurationSheetState extends State<_DurationSheet> {
  final _form = GlobalKey<FormState>();
  late final _text = TextEditingController(text: '${widget.current}');
  void _save() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, int.parse(_text.text));
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Custom clip timer',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Tap to record hands-free. Each new clip stops at this limit; tap again to stop sooner.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('reel-custom-duration'),
              controller: _text,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Seconds',
                helperText: '1–300 seconds per clip',
              ),
              validator: (value) {
                final seconds = int.tryParse(value ?? '');
                return seconds == null ||
                        seconds < 1 ||
                        seconds > ReelSession.maxSeconds
                    ? 'Enter 1–300 seconds'
                    : null;
              },
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('Set timer')),
          ],
        ),
      ),
    ),
  );
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }
}
