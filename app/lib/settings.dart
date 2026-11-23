import 'dart:convert';

import 'package:deskpilot/look.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// How this phone shows DeskPilot. Unlike the deck, which the PC keeps for
/// every phone, these settings belong to this phone only.
class AppSettings {
  const AppSettings({
    this.theme = 'midnight',
    this.spacing = 'normal',
    this.corners = 'round',
    this.fullScreen = false,
    this.keepScreenOn = false,
    this.haptics = true,
    this.clickSound = false,
    this.showMusic = true,
    this.showClock = true,
    this.cardsOnEveryPage = false,
    this.bigPcCards = false,
  });

  /// One of [deckLooks].
  final String theme;

  /// One of [deckSpacings].
  final String spacing;

  /// One of [deckCorners].
  final String corners;
  final bool fullScreen;
  final bool keepScreenOn;
  final bool haptics;
  final bool clickSound;
  final bool showMusic;
  final bool showClock;
  final bool cardsOnEveryPage;
  final bool bigPcCards;

  AppSettings copyWith({
    String? theme,
    String? spacing,
    String? corners,
    bool? fullScreen,
    bool? keepScreenOn,
    bool? haptics,
    bool? clickSound,
    bool? showMusic,
    bool? showClock,
    bool? cardsOnEveryPage,
    bool? bigPcCards,
  }) => AppSettings(
    theme: theme ?? this.theme,
    spacing: spacing ?? this.spacing,
    corners: corners ?? this.corners,
    fullScreen: fullScreen ?? this.fullScreen,
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    haptics: haptics ?? this.haptics,
    clickSound: clickSound ?? this.clickSound,
    showMusic: showMusic ?? this.showMusic,
    showClock: showClock ?? this.showClock,
    cardsOnEveryPage: cardsOnEveryPage ?? this.cardsOnEveryPage,
    bigPcCards: bigPcCards ?? this.bigPcCards,
  );

  Map<String, Object> toJson() => {
    'theme': theme,
    'spacing': spacing,
    'corners': corners,
    'fullScreen': fullScreen,
    'keepScreenOn': keepScreenOn,
    'haptics': haptics,
    'clickSound': clickSound,
    'showMusic': showMusic,
    'showClock': showClock,
    'cardsOnEveryPage': cardsOnEveryPage,
    'bigPcCards': bigPcCards,
  };

  /// Reads saved settings, using the usual value for anything missing or
  /// unknown, so an older or newer app never breaks on them.
  static AppSettings fromJson(Object? json) {
    const usual = AppSettings();
    if (json is! Map<String, Object?>) return usual;
    String pick(String key, Map<String, Object?> known, String fallback) =>
        switch (json[key]) {
          final String value when known.containsKey(value) => value,
          _ => fallback,
        };
    bool flag(String key, bool fallback) => switch (json[key]) {
      final bool value => value,
      _ => fallback,
    };
    return AppSettings(
      theme: pick('theme', deckLooks, usual.theme),
      spacing: pick('spacing', deckSpacings, usual.spacing),
      corners: pick('corners', deckCorners, usual.corners),
      fullScreen: flag('fullScreen', usual.fullScreen),
      keepScreenOn: flag('keepScreenOn', usual.keepScreenOn),
      haptics: flag('haptics', usual.haptics),
      clickSound: flag('clickSound', usual.clickSound),
      showMusic: flag('showMusic', usual.showMusic),
      showClock: flag('showClock', usual.showClock),
      cardsOnEveryPage: flag('cardsOnEveryPage', usual.cardsOnEveryPage),
      bigPcCards: flag('bigPcCards', usual.bigPcCards),
    );
  }
}

const _screen = MethodChannel('deskpilot/screen');

/// Hides or shows Android's bars and keeps the screen on or not, as
/// [settings] say.
Future<void> applyScreen(AppSettings settings) async {
  await SystemChrome.setEnabledSystemUIMode(
    settings.fullScreen
        ? SystemUiMode.immersiveSticky
        : SystemUiMode.edgeToEdge,
  );
  try {
    await _screen.invokeMethod<void>('keepOn', settings.keepScreenOn);
  } on MissingPluginException {
    // Only the Android app can keep the screen on so far; iPhone comes later.
  }
}

/// Keeps [AppSettings] on this phone, next to the paired PC.
class SettingsStore {
  const SettingsStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;
  static const _storageKey = 'settings';

  Future<AppSettings> load() async {
    final text = await _storage.read(key: _storageKey);
    if (text == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(text));
    } on FormatException {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) =>
      _storage.write(key: _storageKey, value: jsonEncode(settings.toJson()));
}
