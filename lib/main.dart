import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  try {
    runApp(GEnglishMotionApp(deps: await AppDependencies.load()));
  } catch (e, st) {
    debugPrint('Startup failed: $e\n$st');
    runApp(const _StartupError());
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.dark(),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Builder(
              builder: (context) => Text(
                'Không mở được ứng dụng. Nhờ bố mẹ cài đặt lại nhé.',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
