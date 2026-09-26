import 'package:flutter/material.dart';

import '../theme/aura_theme.dart';

/// Primary actions use the same shape, hit target, busy state and feedback.
class AuraButton extends StatelessWidget {
  const AuraButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null && !busy,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: onPressed == null ? null : AuraColors.brandGradient,
        color: onPressed == null ? AuraColors.raised : null,
        borderRadius: BorderRadius.circular(16),
      ),
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledForegroundColor: AuraColors.muted,
          minimumSize: const Size(48, 52),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else if (icon != null)
              Icon(icon, size: 20),
            if (busy || icon != null) const SizedBox(width: 10),
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ],
        ),
      ),
    ),
  );
}

class AuraPanel extends StatelessWidget {
  const AuraPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: AuraColors.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: AuraColors.border),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class AuraSectionTitle extends StatelessWidget {
  const AuraSectionTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    ),
  );
}

class AuraEmptyState extends StatelessWidget {
  const AuraEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.onAction,
  });
  final IconData icon;
  final String title, message;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AuraColors.primary.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: AuraColors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (onAction != null && action != null) ...[
              const SizedBox(height: 24),
              AuraButton(label: action!, onPressed: onAction),
            ],
          ],
        ),
      ),
    ),
  );
}

class AuraNotice extends StatelessWidget {
  const AuraNotice(this.message, {super.key, this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: (error ? AuraColors.error : AuraColors.blue).withValues(alpha: .1),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
          size: 20,
          color: error ? AuraColors.error : AuraColors.blue,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: AuraColors.text, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

String auraNumber(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);
