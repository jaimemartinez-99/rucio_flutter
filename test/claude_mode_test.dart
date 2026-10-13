import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucio_flutter/models/claude_mode.dart';
import 'package:rucio_flutter/providers/claude_mode_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Missing or invalid preferences default to economic mode', () async {
    SharedPreferences.setMockInitialValues({
      ClaudeModeNotifier.preferencesKey: 'invalid',
    });
    final notifier = ClaudeModeNotifier();
    await notifier.initialized;
    expect(notifier.state, ClaudeReadingMode.economical);
    notifier.dispose();
  });

  test('User choice during preference loading cannot be overwritten', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = ClaudeModeNotifier();
    await notifier.select(ClaudeReadingMode.deep);
    await notifier.initialized;
    expect(notifier.state, ClaudeReadingMode.deep);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(ClaudeModeNotifier.preferencesKey), 'deep');
    notifier.dispose();
  });

  test('Rapid changes persist the final choice in order', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = ClaudeModeNotifier();
    await notifier.initialized;
    await Future.wait([
      notifier.select(ClaudeReadingMode.deep),
      notifier.select(ClaudeReadingMode.economical),
    ]);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(ClaudeModeNotifier.preferencesKey),
      'economical',
    );
    notifier.dispose();
  });
}
