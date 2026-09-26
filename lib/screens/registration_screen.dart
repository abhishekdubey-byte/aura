import 'package:aura/theme/aura_theme.dart';

import 'package:aura/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/reminder_service.dart';
import '../widgets/aura_brand.dart';
import '../widgets/dob_field.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  DateTime? _dob;
  String? _dobError;
  String _selectedGender = 'Male';
  bool _confirmedAdult = false;
  bool _submitting = false;

  static final RegExp _validName = RegExp(r'^[a-zA-Z0-9_.]{3,20}$');
  final List<String> _genders = ['Male', 'Female', 'Non-Binary', 'Other'];

  Future<void> _submitRegistration() async {
    if (_submitting) return;
    final bool formOk = _formKey.currentState!.validate();
    setState(() {
      _dobError = _dob == null
          ? 'Please add your date of birth'
          : (AgeRules.isAdult(_dob!) ? null : 'AURA is for adults only (18+)');
    });
    if (!formOk || _dobError != null) {
      HapticFeedback.heavyImpact();
      return;
    }
    if (!_confirmedAdult) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please confirm you are 18 or older.'),
          backgroundColor: AuraColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final username = _usernameController.text.trim();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('adult_confirmed', true);
      await prefs.setString('username', username);
      await prefs.setString('full_name', _fullNameController.text.trim());
      await prefs.setString('dob', _dob!.toIso8601String());
      await prefs.setString(
        'age',
        AgeRules.ageOn(_dob!, DateTime.now()).toString(),
      );
      await prefs.setString('gender', _selectedGender);
      await prefs.setBool('registered_flag', true);

      // Now that they're in, ask about streak reminders
      try {
        await ReminderService.requestPermission();
        await ReminderService.schedulePeriodicReminder();
      } catch (e) {
        debugPrint('Reminders unavailable after registration: $e');
      }

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pushAndRemoveUntil(
        context,
        AuraRoute(const CameraScreen()),
        (_) => false,
      );
    } catch (e) {
      debugPrint('Registration failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save your profile. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(
    String label,
    IconData icon, {
    Widget? suffix,
    String? prefix,
  }) => InputDecoration(
    labelText: label,
    prefixText: prefix,
    prefixIcon: Icon(icon),
    suffixIcon: suffix,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuraColors.background,
      body: AuraBackdrop(
        intensity: 0.8,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: AbsorbPointer(
                absorbing: _submitting,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Reveal(child: Center(child: AuraOrb(size: 92))),
                      const SizedBox(height: 16),
                      const Reveal(
                        delay: Duration(milliseconds: 100),
                        child: Text(
                          'Create your AURA',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Reveal(
                        delay: Duration(milliseconds: 180),
                        child: Text(
                          'One minute, then your aura awaits.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: AuraColors.muted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Reveal(
                        delay: const Duration(milliseconds: 260),
                        child: GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _usernameController,
                                style: const TextStyle(color: Colors.white),
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                decoration: _decoration(
                                  'Username',
                                  Icons.alternate_email,
                                ),
                                validator: (value) {
                                  final v = value?.trim() ?? '';
                                  if (v.isEmpty) return 'Pick a username';
                                  if (!_validName.hasMatch(v)) {
                                    return '3–20 letters, numbers, _ or .';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _fullNameController,
                                style: const TextStyle(color: Colors.white),
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.done,
                                decoration: _decoration(
                                  'Full name',
                                  Icons.person_outline,
                                ),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                    ? 'Tell us your name'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                              DobField(
                                value: _dob,
                                errorText: _dobError,
                                onChanged: (dob) => setState(() {
                                  _dob = dob;
                                  _dobError = AgeRules.isAdult(dob)
                                      ? null
                                      : 'AURA is for adults only (18+)';
                                }),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Gender',
                                style: TextStyle(
                                  color: AuraColors.muted,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final g in _genders)
                                    ChoiceChip(
                                      label: Text(g),
                                      selected: g == _selectedGender,
                                      onSelected: (_) =>
                                          setState(() => _selectedGender = g),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'Photos and videos you capture or import in AURA are automatically uploaded to AURA’s server. Offline captures upload when a connection is available.',
                                style: TextStyle(
                                  color: AuraColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // 18+ confirmation
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: _confirmedAdult,
                                onChanged: (value) => setState(
                                  () => _confirmedAdult = value ?? false,
                                ),
                                title: const Text(
                                  'I confirm I am 18 or older.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AuraColors.text,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Reveal(
                        delay: const Duration(milliseconds: 360),
                        child: GradientButton(
                          label: 'Enter AURA',
                          icon: Icons.auto_awesome,
                          busy: _submitting,
                          onPressed: _submitRegistration,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
