import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shows the latest caption (what the voice says) at the bottom of the play
/// area. It replaces itself with the next caption and hides after
/// [visibleFor]. Captions rejected by [filter] are dropped (e.g. the English
/// word of a picture question, which would give the answer away).
class CaptionStrip extends StatefulWidget {
  const CaptionStrip({
    super.key,
    required this.captions,
    this.filter,
    this.clearOn,
    this.visibleFor = const Duration(seconds: 3),
  });

  /// Reserved height, so the lanes above never shift when a caption comes.
  static const double height = 56;

  final Stream<String> captions;
  final bool Function(String caption)? filter;

  /// When this notifies, the current caption is dropped at once (a new
  /// question starts; the previous feedback caption must not linger).
  final Listenable? clearOn;
  final Duration visibleFor;

  @override
  State<CaptionStrip> createState() => _CaptionStripState();
}

class _CaptionStripState extends State<CaptionStrip> {
  StreamSubscription<String>? _sub;
  Timer? _hide;
  String? _text;

  @override
  void initState() {
    super.initState();
    _sub = widget.captions.listen(_onCaption);
    widget.clearOn?.addListener(_clear);
  }

  void _clear() {
    _hide?.cancel();
    _hide = null;
    if (mounted && _text != null) setState(() => _text = null);
  }

  @override
  void didUpdateWidget(CaptionStrip old) {
    super.didUpdateWidget(old);
    if (old.clearOn != widget.clearOn) {
      old.clearOn?.removeListener(_clear);
      widget.clearOn?.addListener(_clear);
    }
    if (old.captions != widget.captions) {
      _sub?.cancel();
      _sub = widget.captions.listen(_onCaption);
    }
  }

  void _onCaption(String text) {
    if (!mounted) return;
    if (!(widget.filter?.call(text) ?? true)) return;
    _hide?.cancel();
    _hide = Timer(widget.visibleFor, () {
      if (mounted) setState(() => _text = null);
    });
    setState(() => _text = text);
  }

  @override
  void dispose() {
    widget.clearOn?.removeListener(_clear);
    _sub?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    return SizedBox(
      height: CaptionStrip.height,
      child: text == null
          ? null
          : Semantics(
              liveRegion: true,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTheme.textStyles.play,
                  ),
                ),
              ),
            ),
    );
  }
}
