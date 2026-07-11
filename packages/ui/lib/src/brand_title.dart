import 'package:flutter/material.dart';

import 'theme.dart';

/// Brand wordmark with the same gold → bridge → accent gradient as ZVBible.
///
/// CSS equivalent:
/// ```css
/// background: linear-gradient(90deg, gold, bridge 55%, accent);
/// background-clip: text; color: transparent;
/// ```
class ZvcommTitle extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// When set, uses these stops instead of the active [ZvPalette] / theme scheme.
  final List<Color>? colors;

  const ZvcommTitle(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.colors,
  });

  /// App-bar sized wordmark.
  const ZvcommTitle.appBar({
    super.key,
    this.text = 'ZVComm',
    this.textAlign,
    this.colors,
  }) : style = const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          height: 1.1,
        );

  static List<Color> colorsFor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Prefer palette tokens when ThemeExtension is available later; fall back
    // to scheme secondary (gold) / tertiary (bridge) / primary (accent).
    return [
      scheme.secondary,
      scheme.tertiary,
      scheme.primary,
    ];
  }

  /// Resolve gradient from a known [ZvPalette] id (or current scheme).
  static List<Color> colorsForPalette(ZvPalette palette) => [
        palette.accentGold,
        palette.bridge,
        palette.accent,
      ];

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(
          style ??
              Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
        );
    final stops = colors ?? colorsFor(context);

    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: stops,
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height));
      },
      child: Text(
        text,
        textAlign: textAlign,
        style: base.copyWith(
          color: Colors.white, // masked by ShaderMask
        ),
      ),
    );
  }
}
