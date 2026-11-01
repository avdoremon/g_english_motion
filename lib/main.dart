import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const GEnglishMotionApp());
}

class GEnglishMotionApp extends StatelessWidget {
  const GEnglishMotionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Tin Tin English',
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: Center(child: Text('Tin Tin English'))),
    );
  }
}
