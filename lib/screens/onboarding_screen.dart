import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/aura_brand.dart';
import 'registration_screen.dart';

/// First-install walkthrough: three swipeable pages with live illustrations.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  final PageController _pages = PageController();
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  double _page = 0;

  static const _content = [
    ('Capture like a pro', 'Instant photos, wallpaper-ready shots in every ratio, and ∞ Boomerangs that loop just right.'),
    ('Reveal your Aura', 'Six on-device AI models read your face, pose, style and light, then turn it into your Aura score.'),
    ('Rise to the top', 'Keep your daily streak alive and climb the global leaderboard.'),
  ];

  @override
  void initState() {
    super.initState();
    _pages.addListener(() => setState(() => _page = _pages.page ?? 0));
  }

  @override
  void dispose() {
    _pages.dispose();
    _loop.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    if (!mounted) return;
    Navigator.pushReplacement(context, AuraRoute(const RegistrationScreen()));
  }

  void _next() {
    if (_page >= _content.length - 1 - 0.01) {
      _finish();
    } else {
      HapticFeedback.selectionClick();
      _pages.nextPage(duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool last = _page.round() == _content.length - 1;
    return Scaffold(
      backgroundColor: Colors.black,
      body: AuraBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: AnimatedOpacity(
                  opacity: last ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: TextButton(
                    onPressed: last ? null : _finish,
                    child: const Text('Skip', style: TextStyle(color: Colors.white70, fontSize: 15)),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: _content.length,
                  onPageChanged: (_) => HapticFeedback.selectionClick(),
                  itemBuilder: (context, i) {
                    final double delta = (i - _page).clamp(-1.0, 1.0);
                    final (title, body) = _content[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          Expanded(
                            child: Transform.translate(
                              // Parallax: the illustration moves slower than the page
                              offset: Offset(delta * 80, 0),
                              child: Opacity(
                                opacity: (1 - delta.abs()).clamp(0.0, 1.0),
                                child: Center(child: _illustration(i)),
                              ),
                            ),
                          ),
                          Text(title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 12),
                          Text(body,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4)),
                          const SizedBox(height: 28),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // Page dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < _content.length; i++)
                    Builder(builder: (context) {
                      final double active = (1 - (i - _page).abs()).clamp(0.0, 1.0);
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8 + 18 * active,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: active > 0.5 ? const LinearGradient(colors: kAuraGradient) : null,
                          color: active > 0.5 ? null : Colors.white24,
                        ),
                      );
                    }),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                child: GradientButton(
                  label: last ? 'Get started' : 'Next',
                  icon: last ? Icons.auto_awesome : Icons.arrow_forward_rounded,
                  onPressed: _next,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _illustration(int i) {
    return AnimatedBuilder(
      animation: _loop,
      builder: (context, _) {
        final double t = _loop.value;
        switch (i) {
          case 0:
            return _cameraIllustration(t);
          case 1:
            return _scoreIllustration(t);
          default:
            return _leaderboardIllustration(t);
        }
      },
    );
  }

  Widget _chip(String text, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 16, color: Colors.white), const SizedBox(width: 6)],
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ]),
      );

  /// Shutter with floating feature chips.
  Widget _cameraIllustration(double t) {
    double bob(double phase) => 8 * math.sin((t + phase) * 2 * math.pi);
    return SizedBox(
      width: 300,
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF7C4DFF), width: 6),
              boxShadow: [BoxShadow(color: kAuraGradient[1].withValues(alpha: 0.4), blurRadius: 40)],
            ),
            child: Center(
              child: Container(
                width: 98 * (0.94 + 0.06 * math.sin(t * 2 * math.pi)),
                height: 98 * (0.94 + 0.06 * math.sin(t * 2 * math.pi)),
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
              ),
            ),
          ),
          Positioned(top: 30 + bob(0), left: 10, child: _chip('Boomerang', icon: Icons.all_inclusive)),
          Positioned(top: 60 + bob(0.33), right: 4, child: _chip('16:9 Wallpaper', icon: Icons.desktop_windows_outlined)),
          Positioned(bottom: 40 + bob(0.66), left: 30, child: _chip('4:5', icon: Icons.crop_portrait)),
          Positioned(bottom: 20 + bob(0.15), right: 30, child: _chip('Zoom', icon: Icons.zoom_in)),
        ],
      ),
    );
  }

  /// Orb with a score counting up and orbiting findings.
  Widget _scoreIllustration(double t) {
    final int score = (99999999 * Curves.easeOutCubic.transform((t * 1.3).clamp(0.0, 1.0))).round() | 1;
    const tags = ['Symmetry', 'Gaze', 'Smile', 'Style', 'Light', 'Pose'];
    return SizedBox(
      width: 300,
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const AuraOrb(size: 150),
          for (int k = 0; k < tags.length; k++)
            Builder(builder: (context) {
              final double a = (t + k / tags.length) * 2 * math.pi;
              return Transform.translate(
                offset: Offset(math.cos(a) * 125, math.sin(a) * 95),
                child: Opacity(opacity: 0.55 + 0.45 * math.sin(a).abs(), child: _chip(tags[k])),
              );
            }),
          Positioned(
            bottom: 0,
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(colors: kAuraGradient).createShader(r),
              child: Text(
                '+${score.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}',
                style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Podium with a streak flame.
  Widget _leaderboardIllustration(double t) {
    Widget bar(double height, String rank, double grow) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(rank, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 6),
            Container(
              width: 70,
              height: height * grow,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                gradient: const LinearGradient(colors: kAuraGradient, begin: Alignment.topCenter, end: Alignment.bottomCenter),
                boxShadow: [BoxShadow(color: kAuraGradient[0].withValues(alpha: 0.35), blurRadius: 20)],
              ),
            ),
          ],
        );
    final double grow = Curves.easeOutBack.transform((t * 2).clamp(0.0, 1.0));
    final double flame = 1 + 0.08 * math.sin(t * 6 * math.pi);
    return SizedBox(
      width: 300,
      height: 300,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [bar(110, '2', grow), const SizedBox(width: 10), bar(160, '1', grow), const SizedBox(width: 10), bar(80, '3', grow)],
          ),
          Positioned(
            top: 10,
            right: 20,
            child: Transform.scale(
              scale: flame,
              child: _chip('7 day streak', icon: Icons.local_fire_department),
            ),
          ),
        ],
      ),
    );
  }
}
