import 'package:flutter/material.dart';

import 'theme.dart';
import 'theme_controller.dart';

/// Grid of ZVBible-style theme swatches (gold → bridge → accent).
class ThemePicker extends StatelessWidget {
  final ThemeController controller;

  const ThemePicker({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final selected = controller.id;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Color themes shared with ZVBible.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final cross = constraints.maxWidth >= 420
                ? 5
                : (constraints.maxWidth >= 320 ? 4 : 3);
            return GridView.count(
              crossAxisCount: cross,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.92,
              children: [
                for (final p in ZvcommTheme.all)
                  _ThemeSwatchTile(
                    palette: p,
                    selected: p.id == selected,
                    onTap: () => controller.setTheme(p.id),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          ZvcommTheme.byId(selected).description,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _ThemeSwatchTile extends StatelessWidget {
  final ZvPalette palette;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeSwatchTile({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.surfaceContainerHighest
          : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? scheme.secondary : scheme.outline,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
          child: Column(
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.black12),
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
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                palette.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
