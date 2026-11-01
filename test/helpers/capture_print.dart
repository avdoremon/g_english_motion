import 'package:flutter/foundation.dart';

/// Runs [body] with `debugPrint` redirected to [sink] (so expected error
/// logs neither pollute the test output nor go unasserted) and restores it
/// afterwards, also when [body] throws. Restoring must happen inside the test
/// body: the widget-test binding checks the override before tearDown runs.
Future<T> captureDebugPrint<T>(
  List<String> sink,
  Future<T> Function() body,
) async {
  final old = debugPrint;
  debugPrint = (String? m, {int? wrapWidth}) => sink.add(m ?? '');
  try {
    return await body();
  } finally {
    debugPrint = old;
  }
}
