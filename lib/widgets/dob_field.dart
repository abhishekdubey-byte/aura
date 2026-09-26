import 'package:aura/theme/aura_theme.dart';
import 'package:flutter/material.dart';

import 'aura_brand.dart';

/// AURA is for adults only.
class AgeRules {
  static const int minimumAge = 18;

  /// Whole years between [dob] and [now].
  static int ageOn(DateTime dob, DateTime now) {
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  static bool isAdult(DateTime dob) => ageOn(dob, DateTime.now()) >= minimumAge;
}

/// Tappable date-of-birth field: opens a dark date picker and shows the
/// chosen date with the resulting age, turning red if under 18.
class DobField extends StatelessWidget {
  const DobField({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final String? errorText;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? DateTime(now.year - 21, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'Your date of birth',
    );
    if (picked != null && context.mounted) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final DateTime? dob = value;
    final int? age = dob == null ? null : AgeRules.ageOn(dob, DateTime.now());
    final bool underage = age != null && age < AgeRules.minimumAge;
    final Color accent = errorText != null || underage
        ? AuraColors.error
        : Colors.white24;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _pick(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent),
            ),
            child: Row(
              children: [
                const Icon(Icons.cake_outlined, color: AuraColors.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    dob == null
                        ? 'Date of birth'
                        : '${dob.day} ${_months[dob.month - 1]} ${dob.year}',
                    style: TextStyle(
                      color: dob == null ? AuraColors.muted : Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (age != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: underage
                          ? null
                          : const LinearGradient(colors: kAuraGradient),
                      color: underage
                          ? AuraColors.error.withValues(alpha: 0.2)
                          : null,
                    ),
                    child: Text(
                      '$age yrs',
                      style: TextStyle(
                        color: underage ? AuraColors.error : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: errorText == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    errorText!,
                    style: const TextStyle(
                      color: AuraColors.error,
                      fontSize: 12.5,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
