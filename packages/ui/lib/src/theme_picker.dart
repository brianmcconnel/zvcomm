import 'package:flutter/material.dart';

import 'theme.dart';
import 'theme_controller.dart';

/// Compact horizontal appearance picker (swatches + selected name).
class ThemePicker extends StatelessWidget {
  final ThemeController controller;

  /// When true, omit the section title (e.g. inside an ExpansionTile).
  final bool dense;

  const ThemePicker({
    super.key,
    required this.controller,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final selected = controller.id;
    final scheme = Theme.of(context).colorScheme;
    final current = ZvcommTheme.byId(selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!dense) ...[
          Row(
            children: [
              Text(
                'Appearance',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              Text(
                current.label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: ZvcommTheme.all.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final p = ZvcommTheme.all[i];
              final isSelected = p.id == selected;
              return _CompactSwatch(
                palette: p,
                selected: isSelected,
                onTap: () => controller.setTheme(p.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CompactSwatch extends StatelessWidget {
  final ZvPalette palette;
  final bool selected;
  final VoidCallback onTap;

  const _CompactSwatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: palette.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  palette.swatchGold,
                  palette.swatchBridge,
                  palette.swatchAccent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: palette.swatchAccent.withValues(alpha: 0.45),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
            child: selected
                ? Icon(
                    Icons.check,
                    size: 18,
                    color: _contrastOn(palette.swatchBridge),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  static Color _contrastOn(Color bg) {
    return bg.computeLuminance() > 0.45 ? Colors.black87 : Colors.white;
  }
}
