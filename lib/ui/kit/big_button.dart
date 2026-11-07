import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Primary call-to-action: pill, ink hard shadow, single-line scaled label.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = AppTheme.yellow,
    this.onColor = AppTheme.ink,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = onColor;
    final style = AppTheme.textStyles.play.copyWith(
      color: fg,
      fontWeight: FontWeight.w700,
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(32),
              boxShadow: const [
                BoxShadow(color: AppTheme.ink, offset: Offset(0, 6)),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(32),
              onTap: onPressed,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 28, color: fg),
                        const SizedBox(width: 12),
                      ],
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(label, maxLines: 1, style: style),
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
