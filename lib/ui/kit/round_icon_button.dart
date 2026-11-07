import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Translucent round icon button; hit area never below [AppTheme.minTarget].
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.size = 56,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hit = size < AppTheme.minTarget ? AppTheme.minTarget : size;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: hit,
          height: hit,
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.glassWhite,
              ),
              child: Icon(icon, size: 26, color: AppTheme.text),
            ),
          ),
        ),
      ),
    );
  }
}
