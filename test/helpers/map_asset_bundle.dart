import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// In-memory [AssetBundle] for tests.
class MapAssetBundle extends AssetBundle {
  MapAssetBundle(this.files);
  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final s = files[key];
    if (s == null) throw FlutterError('Unable to load asset: $key');
    final b = Uint8List.fromList(utf8.encode(s));
    return ByteData.sublistView(b);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final s = files[key];
    if (s == null) throw FlutterError('Unable to load asset: $key');
    return s;
  }
}
