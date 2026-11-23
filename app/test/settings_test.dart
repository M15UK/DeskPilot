import 'package:deskpilot/settings.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings start with the usual look and feel', () {
    const settings = AppSettings();

    expect(settings.theme, 'midnight');
    expect(settings.haptics, isTrue);
    expect(settings.showMusic, isTrue);
    expect(settings.fullScreen, isFalse);
  });

  test('settings are kept on the phone', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const store = SettingsStore();
    final changed = const AppSettings().copyWith(
      theme: 'neon',
      corners: 'square',
      fullScreen: true,
      bigPcCards: true,
    );

    await store.save(changed);
    final loaded = await store.load();

    expect(loaded.toJson(), changed.toJson());
  });

  test('broken or missing settings fall back to the usual ones', () async {
    FlutterSecureStorage.setMockInitialValues({'settings': 'not json'});
    expect((await const SettingsStore().load()).theme, 'midnight');

    expect(
      AppSettings.fromJson({'theme': 'plaid', 'haptics': 'yes'}).toJson(),
      const AppSettings().toJson(),
    );
  });
}
