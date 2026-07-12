import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Load Noto Color Emoji on web and wait until the browser has the face ready.
Future<void> warmEmojiFonts() async {
  // Ensure stylesheet is present (index.html also preloads it).
  final existing = web.document.querySelector('link[data-zvcomm-emoji-font]');
  if (existing == null) {
    final link = web.HTMLLinkElement()
      ..rel = 'stylesheet'
      ..href =
          'https://fonts.googleapis.com/css2?family=Noto+Color+Emoji&display=block';
    link.setAttribute('data-zvcomm-emoji-font', '1');
    web.document.head?.append(link);
  }

  // Wait up to a few seconds for fonts; don't hang the picker forever.
  try {
    await Future.any([
      web.document.fonts.ready.toDart,
      Future<void>.delayed(const Duration(seconds: 4)),
    ]);
  } catch (_) {}

  try {
    await web.document.fonts.load('32px "Noto Color Emoji"').toDart;
  } catch (_) {}

  try {
    // Warm a few common code points so the first paint has glyphs.
    await web.document.fonts.load('32px "Noto Color Emoji"').toDart;
  } catch (_) {}

  try {
    await web.document.fonts.ready.toDart;
  } catch (_) {}

  await Future<void>.delayed(const Duration(milliseconds: 48));
}
