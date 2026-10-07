import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReadingTheme { light, sepia, dark, night, paper, forest, ocean, rose }

enum ReadingFont { serif, sansSerif, monospace }

enum ReadingAlignment { justified, left }

enum ReadingLayout { singleColumn, twoColumns }

class ReadingSettings {
  final ReadingTheme theme;
  final ReadingFont font;
  final ReadingAlignment alignment;
  final ReadingLayout layout;
  final double fontSize;
  final double lineHeight;
  final double marginH;
  final double paragraphSpacing;

  const ReadingSettings({
    this.theme = ReadingTheme.light,
    this.font = ReadingFont.serif,
    this.alignment = ReadingAlignment.justified,
    this.layout = ReadingLayout.singleColumn,
    this.fontSize = 16,
    this.lineHeight = 1.5,
    this.marginH = 0,
    this.paragraphSpacing = 0.8,
  });

  ReadingSettings copyWith({
    ReadingTheme? theme,
    ReadingFont? font,
    ReadingAlignment? alignment,
    ReadingLayout? layout,
    double? fontSize,
    double? lineHeight,
    double? marginH,
    double? paragraphSpacing,
  }) {
    return ReadingSettings(
      theme: theme ?? this.theme,
      font: font ?? this.font,
      alignment: alignment ?? this.alignment,
      layout: layout ?? this.layout,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      marginH: marginH ?? this.marginH,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
    );
  }

  Map<String, String> get colors => themeColors[theme]!;

  static const themeColors = {
    ReadingTheme.light: {'label': 'Light', 'bg': '#FFFFFF', 'text': '#1A1A2E'},
    ReadingTheme.sepia: {'label': 'Sepia', 'bg': '#F5EAD7', 'text': '#3D2B1F'},
    ReadingTheme.dark: {'label': 'Dark', 'bg': '#1E1E2E', 'text': '#CDD6F4'},
    ReadingTheme.night: {'label': 'Night', 'bg': '#0A0A0F', 'text': '#8899AA'},
    ReadingTheme.paper: {'label': 'Paper', 'bg': '#F7F4ED', 'text': '#27231D'},
    ReadingTheme.forest: {
      'label': 'Forest',
      'bg': '#14251F',
      'text': '#D7E8D2',
    },
    ReadingTheme.ocean: {'label': 'Ocean', 'bg': '#102432', 'text': '#C7E6F7'},
    ReadingTheme.rose: {'label': 'Rose', 'bg': '#FCEFF1', 'text': '#492C36'},
  };

  String get fontFamily => switch (font) {
    ReadingFont.serif => 'Georgia, "Times New Roman", serif',
    ReadingFont.sansSerif => 'Arial, Helvetica, sans-serif',
    ReadingFont.monospace => '"Courier New", monospace',
  };

  String buildCss() {
    final c = colors;
    final textAlign = alignment == ReadingAlignment.justified
        ? 'justify'
        : 'left';
    return """
      html, body { background: ${c['bg']} !important; color: ${c['text']} !important; }
      body { font-family: $fontFamily !important; font-size: ${fontSize}px !important; line-height: $lineHeight !important; }
      p, li, blockquote, td, th { font-family: inherit !important; font-size: inherit !important; line-height: inherit !important; }
      body { margin: 0 !important; padding: 10px ${marginH}px 20px !important; box-sizing: border-box !important; text-align: $textAlign !important; overflow-x: hidden !important; }
      img, table, pre { max-width: 100% !important; break-inside: avoid !important; }
      p { margin-bottom: ${paragraphSpacing}em !important; }
      h1, h2, h3, h4, h5, h6 { break-after: avoid !important; }
    """;
  }
}

class SettingsNotifier extends StateNotifier<ReadingSettings> {
  static const _keyTheme = 'reading_theme';
  static const _keyFont = 'reading_font';
  static const _keyAlignment = 'reading_alignment';
  static const _keyLayout = 'reading_layout';
  static const _keyFontSize = 'reading_font_size';
  static const _keyLineHeight = 'reading_line_height';
  static const _keyMarginH = 'reading_margin_h';
  static const _keyParagraphSpacing = 'reading_paragraph_spacing';

  late final Future<void> initialized;

  SettingsNotifier() : super(const ReadingSettings()) {
    initialized = _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = ReadingSettings(
      theme: _enumValue(ReadingTheme.values, prefs.getInt(_keyTheme)),
      font: _enumValue(ReadingFont.values, prefs.getInt(_keyFont)),
      alignment: _enumValue(
        ReadingAlignment.values,
        prefs.getInt(_keyAlignment),
      ),
      layout: _enumValue(ReadingLayout.values, prefs.getInt(_keyLayout)),
      fontSize: prefs.getDouble(_keyFontSize) ?? 16,
      lineHeight: prefs.getDouble(_keyLineHeight) ?? 1.5,
      marginH: prefs.getDouble(_keyMarginH) ?? 0,
      paragraphSpacing: prefs.getDouble(_keyParagraphSpacing) ?? 0.8,
    );
  }

  T _enumValue<T extends Enum>(List<T> values, int? index) {
    if (index == null || index < 0 || index >= values.length) {
      return values.first;
    }
    return values[index];
  }

  Future<void> setTheme(ReadingTheme value) => _update(
    state.copyWith(theme: value),
    (prefs) => prefs.setInt(_keyTheme, value.index),
  );

  Future<void> setFont(ReadingFont value) => _update(
    state.copyWith(font: value),
    (prefs) => prefs.setInt(_keyFont, value.index),
  );

  Future<void> setAlignment(ReadingAlignment value) => _update(
    state.copyWith(alignment: value),
    (prefs) => prefs.setInt(_keyAlignment, value.index),
  );

  Future<void> setLayout(ReadingLayout value) => _update(
    state.copyWith(layout: value),
    (prefs) => prefs.setInt(_keyLayout, value.index),
  );

  Future<void> setFontSize(double value) => _update(
    state.copyWith(fontSize: value),
    (prefs) => prefs.setDouble(_keyFontSize, value),
  );

  Future<void> setLineHeight(double value) => _update(
    state.copyWith(lineHeight: value),
    (prefs) => prefs.setDouble(_keyLineHeight, value),
  );

  Future<void> setMarginH(double value) => _update(
    state.copyWith(marginH: value),
    (prefs) => prefs.setDouble(_keyMarginH, value),
  );

  Future<void> setParagraphSpacing(double value) => _update(
    state.copyWith(paragraphSpacing: value),
    (prefs) => prefs.setDouble(_keyParagraphSpacing, value),
  );

  Future<void> _update(
    ReadingSettings next,
    Future<bool> Function(SharedPreferences prefs) persist,
  ) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await persist(prefs);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, ReadingSettings>((ref) {
      return SettingsNotifier();
    });
