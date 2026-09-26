import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/reminder_service.dart';
import '../theme/aura_theme.dart';
import '../widgets/aura_controls.dart';
import '../widgets/slang_style_picker.dart';
import '../models/slang_style.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _ready = false, _watermark = false, _reminders = true;
  String _save = 'Both', _name = 'Your profile', _username = '';
  String? _error;
  SlangStyle _slangStyle = SlangStyle.neutral;
  final _watermarkController = TextEditingController();
  SharedPreferences? _prefs;
  Future<void> _writes = Future.value();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _watermark = prefs.getBool('watermark_enabled') ?? false;
        _reminders = prefs.getBool('reminders_enabled') ?? true;
        final saved = prefs.getString('save_preference') ?? 'Both';
        _save = saved == 'Screenshot'
            ? 'Edited'
            : (['Original', 'Edited', 'Both'].contains(saved) ? saved : 'Both');
        _name = prefs.getString('full_name') ?? 'Your profile';
        _username = prefs.getString('username') ?? '';
        _slangStyle = SlangStyle.fromStored(
          prefs.getString(SlangStyle.preferenceKey),
        );
        _watermarkController.text =
            prefs.getString('custom_watermark') ?? 'Made with AURA';
        _ready = true;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Settings could not be loaded. Please try again.',
        );
      }
    }
  }

  void _write(Future<bool> Function(SharedPreferences) write) {
    _writes = _writes.then((_) async {
      try {
        if (!await write(_prefs!)) throw StateError('Not saved');
      } catch (_) {
        if (mounted) {
          setState(
            () => _error =
                'That change could not be saved. Try changing it again.',
          );
        }
      }
    });
  }

  Future<void> _setReminders(bool value) async {
    setState(() => _reminders = value);
    _write((p) => p.setBool('reminders_enabled', value));
    try {
      if (value) {
        await ReminderService.requestPermission();
        await ReminderService.schedulePeriodicReminder();
      } else {
        await ReminderService.cancel();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Check notification access in your phone settings to enable reminders.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: !_ready
        ? (_error == null
              ? const Center(child: CircularProgressIndicator())
              : AuraEmptyState(
                  icon: Icons.settings_outlined,
                  title: 'Settings unavailable',
                  message: _error!,
                  action: 'Try again',
                  onAction: _load,
                ))
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  AuraPanel(
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(
                            gradient: AuraColors.brandGradient,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _username.isEmpty
                                    ? 'Make every moment yours.'
                                    : '@$_username',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    AuraNotice(_error!, error: true),
                  ],
                  const AuraSectionTitle(
                    'Capture & save',
                    subtitle: 'Your photos, your finishing touches.',
                  ),
                  AuraPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Photo watermark'),
                          subtitle: const Text(
                            'Add your signature to saved photos',
                          ),
                          secondary: const Icon(
                            Icons.auto_awesome_outlined,
                            color: AuraColors.blue,
                          ),
                          value: _watermark,
                          onChanged: (value) {
                            setState(() => _watermark = value);
                            _write(
                              (p) => p.setBool('watermark_enabled', value),
                            );
                          },
                        ),
                        if (_watermark)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: TextField(
                              controller: _watermarkController,
                              maxLength: 100,
                              decoration: const InputDecoration(
                                labelText: 'Your signature',
                                helperText: 'Saved automatically',
                              ),
                              onChanged: (value) => _write(
                                (p) => p.setString('custom_watermark', value),
                              ),
                            ),
                          ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(_save),
                            initialValue: _save,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Save Aura results',
                              prefixIcon: Icon(Icons.photo_library_outlined),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Original',
                                child: Text('Original photo'),
                              ),
                              DropdownMenuItem(
                                value: 'Edited',
                                child: Text('Photo with score'),
                              ),
                              DropdownMenuItem(
                                value: 'Both',
                                child: Text('Original + photo with score'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _save = value);
                              _write(
                                (p) => p.setString('save_preference', value),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const AuraSectionTitle('Your Aura captions'),
                  AuraPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SlangStylePicker(
                          value: _slangStyle,
                          onChanged: (value) {
                            setState(() => _slangStyle = value);
                            _write(
                              (p) => p.setString(
                                SlangStyle.preferenceKey,
                                value.name,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Choose the wording you like. You can change it for each photo. Points stay the same.',
                        ),
                      ],
                    ),
                  ),
                  const AuraSectionTitle('Stay inspired'),
                  AuraPanel(
                    padding: EdgeInsets.zero,
                    child: SwitchListTile(
                      title: const Text('Daily reminder'),
                      subtitle: const Text(
                        'A little nudge to keep your streak going',
                      ),
                      secondary: const Icon(
                        Icons.notifications_none_rounded,
                        color: AuraColors.yellow,
                      ),
                      value: _reminders,
                      onChanged: _setReminders,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const AuraNotice(
                    'Aura is a playful take on your photo’s style, pose and lighting. It isn’t a measure of your worth.',
                  ),
                  const SizedBox(height: 28),
                  const Center(
                    child: Text(
                      'AURA · Made for your moments',
                      style: TextStyle(fontSize: 12, color: AuraColors.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
  );

  @override
  void dispose() {
    _watermarkController.dispose();
    super.dispose();
  }
}
