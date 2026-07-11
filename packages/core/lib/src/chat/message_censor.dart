import 'package:censor_it/censor_it.dart';

export 'package:censor_it/censor_it.dart'
    show CensorIt, CensorPattern, LanguagePattern;

/// Profanity filter applied to chat plaintext.
///
/// Used **before encryption** (outbound) and **after decryption** (inbound)
/// so ciphertext never carries raw swear words and UI never shows them either.
///
/// Backed by [`censor_it`](https://pub.dev/packages/censor_it) (MIT).
final class MessageCensor {
  MessageCensor._();

  /// Global on/off switch (default enabled).
  static bool enabled = true;

  /// Pattern set for matching (default: all bundled languages).
  static CensorPattern pattern = LanguagePattern.all;

  /// Mask character for replacements (single code unit / grapheme).
  static String maskChar = '*';

  /// Returns [text] with profanity masked, or unchanged when [enabled] is false.
  static String censor(String text) {
    if (!enabled || text.isEmpty) return text;
    return CensorIt.mask(text, char: maskChar, pattern: pattern).censored;
  }

  /// Whether [text] contains any matched profanity under the current [pattern].
  static bool hasProfanity(String text) {
    if (!enabled || text.isEmpty) return false;
    return CensorIt.mask(text, pattern: pattern).hasProfanity;
  }

  /// Reset to defaults (useful in tests).
  static void resetDefaults() {
    enabled = true;
    pattern = LanguagePattern.all;
    maskChar = '*';
  }
}
