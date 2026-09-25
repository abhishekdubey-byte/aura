import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../widgets/aura_brand.dart';
import '../widgets/dob_field.dart';

/// Shown once to people who registered before AURA became 18+.
class AgeGateScreen extends StatefulWidget {
  const AgeGateScreen({super.key});

  @override
  State<AgeGateScreen> createState() => _AgeGateScreenState();
}

class _AgeGateScreenState extends State<AgeGateScreen> {
  DateTime? _dob;
  String? _error;
  bool _blocked = false;

  Future<void> _confirm() async {
    final dob = _dob;
    if (dob == null) {
      setState(() => _error = 'Please add your date of birth');
      return;
    }
    if (!AgeRules.isAdult(dob)) {
      HapticFeedback.heavyImpact();
      setState(() => _blocked = true);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('adult_confirmed', true);
    await prefs.setString('dob', dob.toIso8601String());
    await prefs.setString('age', AgeRules.ageOn(dob, DateTime.now()).toString());
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.pushReplacement(context, AuraRoute(const CameraScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AuraBackdrop(
        intensity: _blocked ? 0.3 : 0.8,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _blocked ? _blockedView() : _confirmView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _confirmView() {
    return Column(
      key: const ValueKey('confirm'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: AuraOrb(size: 96)),
        const SizedBox(height: 24),
        const Text('AURA is now 18+',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        const Text('Please confirm your date of birth to keep using AURA.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.4)),
        const SizedBox(height: 28),
        GlassCard(
          child: DobField(
            value: _dob,
            errorText: _error,
            onChanged: (dob) => setState(() {
              _dob = dob;
              _error = null;
            }),
          ),
        ),
        const SizedBox(height: 24),
        GradientButton(label: 'Continue', icon: Icons.arrow_forward_rounded, onPressed: _confirm),
      ],
    );
  }

  Widget _blockedView() {
    return Column(
      key: const ValueKey('blocked'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.redAccent, width: 3),
          ),
          alignment: Alignment.center,
          child: const Text('18+', style: TextStyle(color: Colors.redAccent, fontSize: 30, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 24),
        const Text('AURA is for adults only',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        const Text('You need to be 18 or older to use this app.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 15)),
        const SizedBox(height: 32),
        TextButton(
          onPressed: () => SystemNavigator.pop(),
          child: const Text('Close AURA', style: TextStyle(color: Colors.white70, fontSize: 16)),
        ),
      ],
    );
  }
}
