import 'dart:async';

import 'package:aura/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/reminder_service.dart';
import '../widgets/aura_brand.dart';
import '../widgets/dob_field.dart';

enum _NameState { idle, checking, available, taken, invalid }

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

  _NameState _nameState = _NameState.idle;
  Timer? _nameDebounce;
  int _nameCheck = 0;

  static final RegExp _validName = RegExp(r'^[a-zA-Z0-9_.]{3,20}$');
  final List<String> _genders = ['Male', 'Female', 'Non-Binary', 'Other'];

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_onUsernameChanged);
  }

  void _onUsernameChanged() {
    _nameDebounce?.cancel();
    final name = _usernameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameState = _NameState.idle);
      return;
    }
    if (!_validName.hasMatch(name)) {
      setState(() => _nameState = _NameState.invalid);
      return;
    }
    setState(() => _nameState = _NameState.checking);
    _nameDebounce = Timer(const Duration(milliseconds: 500), () async {
      final int check = ++_nameCheck;
      final bool? taken = await _isTaken(name);
      if (!mounted || check != _nameCheck) return;
      setState(() => _nameState = taken == true ? _NameState.taken : _NameState.available);
    });
  }

  /// null when offline / unknown.
  Future<bool?> _isTaken(String username) async {
    try {
      final response = await Supabase.instance.client.from('leaderboard').select('username').eq('username', username).limit(1);
      return response.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking username uniqueness: $e');
      return null;
    }
  }

  Future<void> _submitRegistration() async {
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
        const SnackBar(content: Text('Please confirm you are 18 or older.'), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final username = _usernameController.text.trim();
    setState(() => _submitting = true);
    if (await _isTaken(username) == true) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _nameState = _NameState.taken;
      });
      _formKey.currentState!.validate();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('registered_flag', true);
    await prefs.setBool('adult_confirmed', true);
    await prefs.setString('username', username);
    await prefs.setString('full_name', _fullNameController.text.trim());
    await prefs.setString('dob', _dob!.toIso8601String());
    await prefs.setString('age', AgeRules.ageOn(_dob!, DateTime.now()).toString());
    await prefs.setString('gender', _selectedGender);

    // Now that they're in, ask about streak reminders
    await ReminderService.requestPermission();

    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.pushAndRemoveUntil(context, AuraRoute(const CameraScreen()), (_) => false);
  }

  @override
  void dispose() {
    _nameDebounce?.cancel();
    _usernameController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, IconData icon, {Widget? suffix, String? prefix}) => InputDecoration(
        labelText: label,
        prefixText: prefix,
        prefixIcon: Icon(icon, color: Colors.white60),
        suffixIcon: suffix,
        labelStyle: const TextStyle(color: Colors.white60),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white24)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE040FB), width: 1.6)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.redAccent)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.redAccent, width: 1.6)),
      );

  Widget? _nameIndicator() {
    switch (_nameState) {
      case _NameState.checking:
        return const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
        );
      case _NameState.available:
        return const Icon(Icons.check_circle, color: Colors.greenAccent);
      case _NameState.taken:
      case _NameState.invalid:
        return const Icon(Icons.cancel, color: Colors.redAccent);
      case _NameState.idle:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AuraBackdrop(
        intensity: 0.8,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Reveal(child: Center(child: AuraOrb(size: 92))),
                    const SizedBox(height: 16),
                    const Reveal(
                      delay: Duration(milliseconds: 100),
                      child: Text('Create your AURA',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
                    ),
                    const SizedBox(height: 6),
                    const Reveal(
                      delay: Duration(milliseconds: 180),
                      child: Text('One minute, then your aura awaits.',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.white60)),
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
                              decoration: _decoration('Username', Icons.alternate_email, suffix: _nameIndicator()),
                              validator: (value) {
                                final v = value?.trim() ?? '';
                                if (v.isEmpty) return 'Pick a username';
                                if (!_validName.hasMatch(v)) return '3–20 letters, numbers, _ or .';
                                if (_nameState == _NameState.taken) return 'That username is taken';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _fullNameController,
                              style: const TextStyle(color: Colors.white),
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.done,
                              decoration: _decoration('Full name', Icons.person_outline),
                              validator: (value) => value == null || value.trim().isEmpty ? 'Tell us your name' : null,
                            ),
                            const SizedBox(height: 14),
                            DobField(
                              value: _dob,
                              errorText: _dobError,
                              onChanged: (dob) => setState(() {
                                _dob = dob;
                                _dobError = AgeRules.isAdult(dob) ? null : 'AURA is for adults only (18+)';
                              }),
                            ),
                            const SizedBox(height: 16),
                            const Text('Gender', style: TextStyle(color: Colors.white60, fontSize: 13)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final g in _genders)
                                  GestureDetector(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      setState(() => _selectedGender = g);
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
                                        gradient: g == _selectedGender ? const LinearGradient(colors: kAuraGradient) : null,
                                        color: g == _selectedGender ? null : Colors.white.withValues(alpha: 0.06),
                                        border: Border.all(color: g == _selectedGender ? Colors.transparent : Colors.white24),
                                      ),
                                      child: Text(g,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: g == _selectedGender ? FontWeight.w800 : FontWeight.w500,
                                          )),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            // 18+ confirmation
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _confirmedAdult = !_confirmedAdult);
                              },
                              child: Row(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(7),
                                      gradient: _confirmedAdult ? const LinearGradient(colors: kAuraGradient) : null,
                                      border: Border.all(color: _confirmedAdult ? Colors.transparent : Colors.white38, width: 1.6),
                                    ),
                                    child: _confirmedAdult ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text('I confirm I am 18 years of age or older.',
                                        style: TextStyle(color: Colors.white, fontSize: 14.5)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.7)),
                                    ),
                                    child: const Text('18+', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 12)),
                                  ),
                                ],
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
    );
  }
}
