import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'emoji_data.dart';
import 'emoji_font_stub.dart' if (dart.library.js_interop) 'emoji_font_web.dart'
    as platform;

/// Loads / warms emoji fonts so the picker never flashes missing-glyph boxes.
abstract final class EmojiGlyphs {
  static Future<void>? _warm;
  static bool ready = false;

  /// System + web fallbacks that provide color emoji.
  static const fontFamilyFallback = <String>[
    'Noto Color Emoji',
    'Apple Color Emoji',
    'Segoe UI Emoji',
    'Segoe UI Symbol',
    'Android Emoji',
    'EmojiOne Color',
    'Twemoji Mozilla',
  ];

  /// Text style for rendering emoji glyphs.
  static TextStyle style({double fontSize = 22, double height = 1.15}) {
    return TextStyle(
      fontSize: fontSize,
      height: height,
      // Prefer an explicit color-emoji family once preloaded on web.
      fontFamily: kIsWeb ? 'Noto Color Emoji' : null,
      fontFamilyFallback: fontFamilyFallback,
    );
  }

  /// Ensure fonts are loaded and a sample of glyphs is rasterized.
  /// Safe to call multiple times; concurrent callers share one future.
  static Future<void> ensureReady() {
    return _warm ??= _doWarm();
  }

  static Future<void> _doWarm() async {
    try {
      await platform.warmEmojiFonts();
    } catch (_) {
      // Fall through — system fallbacks may still work.
    }

    // Force layout of a representative set so the first visible frame
    // already has glyph bitmaps (avoids □ with X flash).
    try {
      final sample = <String>{
        ...EmojiCatalog.quickReactions,
        for (final c in EmojiCatalog.categories) ...c.emojis.take(32),
      };
      final tp = TextPainter(
        text: TextSpan(
          text: sample.join(),
          style: style(fontSize: 28),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 10000);
      // Touch metrics so the engine materializes glyphs.
      // ignore: unnecessary_statements
      tp.width;
      // ignore: unnecessary_statements
      tp.height;
    } catch (_) {}

    ready = true;
  }
}
