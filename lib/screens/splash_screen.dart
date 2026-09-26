import 'package:aura/theme/aura_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../widgets/aura_brand.dart';
import 'age_gate_screen.dart';
import 'onboarding_screen.dart';
import 'registration_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // Drives the intro choreography (orb, letters, tagline)
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  static const String _word = 'AURA';
  late final List<Animation<double>> _letters = [
    for (int i = 0; i < _word.length; i++)
      _interval(0.25 + i * 0.08, 0.6 + i * 0.08),
  ];

  @override
  void initState() {
    super.initState();
    _intro.forward();
    _continue();
  }

  Future<void> _continue() async {
    final prefs = await SharedPreferences.getInstance();
    final bool registered = prefs.getBool('registered_flag') ?? false;
    final bool adult = prefs.getBool('adult_confirmed') ?? false;
    final bool onboarded = prefs.getBool('onboarding_seen') ?? false;

    // First launch gets the full intro; later launches are snappy
    final Duration minimum = registered
        ? const Duration(milliseconds: 1100)
        : const Duration(milliseconds: 2300);
    await Future.wait([appReady, Future.delayed(minimum)]);
    if (!mounted) return;

    final Widget next;
    if (!registered) {
      next = onboarded ? const RegistrationScreen() : const OnboardingScreen();
    } else if (!adult) {
      // Registered before AURA became 18+: confirm age once
      next = const AgeGateScreen();
    } else {
      next = const CameraScreen();
    }
    HapticFeedback.lightImpact();
    Navigator.pushReplacement(context, AuraRoute(next));
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Animation<double> _interval(
    double begin,
    double end, [
    Curve curve = Curves.easeOutCubic,
  ]) => CurvedAnimation(
    parent: _intro,
    curve: Interval(begin, end, curve: curve),
  );

  @override
  Widget build(BuildContext context) {
    final orb = _interval(0.0, 0.55, Curves.easeOutBack);
    final tagline = _interval(0.62, 0.9);
    final footer = _interval(0.75, 1.0);

    return Scaffold(
      backgroundColor: AuraColors.background,
      body: AuraBackdrop(
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: orb,
                      builder: (context, child) => Opacity(
                        opacity: orb.value.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: 0.6 + 0.4 * orb.value,
                          child: child,
                        ),
                      ),
                      child: const AuraOrb(size: 132),
                    ),
                    const SizedBox(height: 28),
                    // Letters rise in one after another
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < _word.length; i++)
                          AnimatedBuilder(
                            animation: _letters[i],
                            builder: (context, child) {
                              final double v = _letters[i].value;
                              return Opacity(
                                opacity: v.clamp(0.0, 1.0),
                                child: Transform.translate(
                                  offset: Offset(0, 18 * (1 - v)),
                                  child: child,
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: ShimmerText(
                                _word[i],
                                style: const TextStyle(
                                  fontSize: 52,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FadeTransition(
                      opacity: tagline,
                      child: const Text(
                        'Discover your aura',
                        style: TextStyle(
                          color: AuraColors.muted,
                          fontSize: 16,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Real start-up progress + brand line
              Align(
                alignment: Alignment.bottomCenter,
                child: FadeTransition(
                  opacity: footer,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 36),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 120,
                          child: ValueListenableBuilder<double>(
                            valueListenable: appReadyProgress,
                            builder: (context, progress, _) =>
                                TweenAnimationBuilder<double>(
                                  tween: Tween(end: progress),
                                  duration: const Duration(milliseconds: 400),
                                  builder: (context, value, _) => ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: Stack(
                                      children: [
                                        Container(
                                          height: 3,
                                          color: Colors.white12,
                                        ),
                                        FractionallySizedBox(
                                          widthFactor: value.clamp(0.05, 1.0),
                                          child: Container(
                                            height: 3,
                                            decoration: const BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: kAuraGradient,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.14),
                            ),
                          ),
                          child: const Text(
                            'A Product By GreedHunter',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1.1,
                              color: AuraColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
