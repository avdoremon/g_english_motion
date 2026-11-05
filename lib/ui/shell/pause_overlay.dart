import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PauseOverlay extends StatelessWidget {
  const PauseOverlay({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.pauseScrim,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            message,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
