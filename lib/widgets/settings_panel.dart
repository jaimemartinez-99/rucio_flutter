import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';

class SettingsPanel extends ConsumerWidget {
  const SettingsPanel({
    super.key,
    required this.onCssChanged,
    required this.onLayoutChanged,
    this.onStartAudio,
  });

  final void Function(String css) onCssChanged;
  final ValueChanged<ReadingLayout> onLayoutChanged;
  final VoidCallback? onStartAudio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        if (onStartAudio != null) ...[
          FilledButton.icon(
            onPressed: onStartAudio,
            icon: const Icon(Icons.headphones_outlined),
            label: const Text('Iniciar Audiorucio'),
          ),
          const SizedBox(height: 24),
        ],
        Text('Reading settings', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 24),
        const _SectionTitle(title: 'Color theme'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ReadingTheme.values.map((theme) {
            final colors = ReadingSettings.themeColors[theme]!;
            return ChoiceChip(
              label: Text(colors['label']!),
              selected: settings.theme == theme,
              avatar: CircleAvatar(
                radius: 10,
                backgroundColor: Color(
                  int.parse(colors['bg']!.replaceFirst('#', '0xFF')),
                ),
              ),
              onSelected: (_) {
                notifier.setTheme(theme);
                onCssChanged(settings.copyWith(theme: theme).buildCss());
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 28),
        const _SectionTitle(title: 'Text format'),
        const SizedBox(height: 10),
        SegmentedButton<ReadingLayout>(
          segments: const [
            ButtonSegment(
              value: ReadingLayout.singleColumn,
              icon: Icon(Icons.view_agenda_outlined),
              label: Text('One column'),
            ),
            ButtonSegment(
              value: ReadingLayout.twoColumns,
              icon: Icon(Icons.view_column_outlined),
              label: Text('Two columns'),
            ),
          ],
          selected: {settings.layout},
          onSelectionChanged: (value) {
            final layout = value.first;
            notifier.setLayout(layout);
            onLayoutChanged(layout);
          },
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<ReadingFont>(
          initialValue: settings.font,
          decoration: const InputDecoration(labelText: 'Font family'),
          items: const [
            DropdownMenuItem(value: ReadingFont.serif, child: Text('Serif')),
            DropdownMenuItem(
              value: ReadingFont.sansSerif,
              child: Text('Sans serif'),
            ),
            DropdownMenuItem(
              value: ReadingFont.monospace,
              child: Text('Monospace'),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            notifier.setFont(value);
            onCssChanged(settings.copyWith(font: value).buildCss());
          },
        ),
        const SizedBox(height: 16),
        SegmentedButton<ReadingAlignment>(
          segments: const [
            ButtonSegment(
              value: ReadingAlignment.justified,
              icon: Icon(Icons.format_align_justify),
              label: Text('Justified'),
            ),
            ButtonSegment(
              value: ReadingAlignment.left,
              icon: Icon(Icons.format_align_left),
              label: Text('Left'),
            ),
          ],
          selected: {settings.alignment},
          onSelectionChanged: (value) {
            final alignment = value.first;
            notifier.setAlignment(alignment);
            onCssChanged(settings.copyWith(alignment: alignment).buildCss());
          },
        ),
        const SizedBox(height: 28),
        const _SectionTitle(title: 'Typography'),
        _SettingsSlider(
          label: 'Font size',
          valueLabel: '${settings.fontSize.round()} px',
          value: settings.fontSize,
          min: 12,
          max: 30,
          divisions: 18,
          onChanged: (value) {
            notifier.setFontSize(value);
            onCssChanged(settings.copyWith(fontSize: value).buildCss());
          },
        ),
        _SettingsSlider(
          label: 'Line height',
          valueLabel: '${settings.lineHeight.toStringAsFixed(1)}x',
          value: settings.lineHeight,
          min: 1.2,
          max: 2.5,
          divisions: 13,
          onChanged: (value) {
            notifier.setLineHeight(value);
            onCssChanged(settings.copyWith(lineHeight: value).buildCss());
          },
        ),
        _SettingsSlider(
          label: 'Paragraph spacing',
          valueLabel: '${settings.paragraphSpacing.toStringAsFixed(1)} em',
          value: settings.paragraphSpacing,
          min: 0.2,
          max: 2,
          divisions: 9,
          onChanged: (value) {
            notifier.setParagraphSpacing(value);
            onCssChanged(settings.copyWith(paragraphSpacing: value).buildCss());
          },
        ),
        const SizedBox(height: 12),
        const _SectionTitle(title: 'Page'),
        _SettingsSlider(
          label: 'Horizontal margins',
          valueLabel: '${settings.marginH.round()} px',
          value: settings.marginH,
          min: 0,
          max: 120,
          divisions: 15,
          onChanged: (value) {
            notifier.setMarginH(value);
            onCssChanged(settings.copyWith(marginH: value).buildCss());
          },
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _SettingsSlider extends StatelessWidget {
  const _SettingsSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(label), Text(valueLabel)],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
