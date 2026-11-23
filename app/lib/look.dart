import 'package:deskpilot/deck.dart';
import 'package:flutter/material.dart';

/// DeskPilot's dark look: a near black screen, slightly lighter cards, and
/// one bright color per kind of thing.
abstract final class DeckLook {
  static const background = Color(0xFF0B0D12);
  static const rail = Color(0xFF0F1218);
  static const card = Color(0xFF161A22);
  static const cardBorder = Color(0xFF222736);
  static const text = Color(0xFFEDEFF5);
  static const muted = Color(0xFF8A90A2);
  static const radius = 16.0;
}

/// The colors a button can have. The PC accepts the same names.
const deckColors = {
  'red': Color(0xFFFF5A5F),
  'amber': Color(0xFFFFB547),
  'green': Color(0xFF4ADE80),
  'teal': Color(0xFF2BD4B4),
  'blue': Color(0xFF4C8DFF),
  'purple': Color(0xFF9B7BFF),
  'pink': Color(0xFFFF6FB1),
  'gray': Color(0xFF8A90A2),
};

/// The icons a button can have, by the name saved in the deck.
const deckIcons = {
  'play_arrow': Icons.play_arrow_rounded,
  'pause': Icons.pause_rounded,
  'skip_previous': Icons.skip_previous_rounded,
  'skip_next': Icons.skip_next_rounded,
  'volume_up': Icons.volume_up_rounded,
  'volume_down': Icons.volume_down_rounded,
  'volume_off': Icons.volume_off_rounded,
  'music_note': Icons.music_note_rounded,
  'mic': Icons.mic_rounded,
  'mic_off': Icons.mic_off_rounded,
  'headset': Icons.headset_rounded,
  'headset_off': Icons.headset_off_rounded,
  'chat': Icons.chat_rounded,
  'videocam': Icons.videocam_rounded,
  'camera': Icons.camera_alt_rounded,
  'screenshot': Icons.screenshot_monitor_rounded,
  'keyboard': Icons.keyboard_rounded,
  'open_in_new': Icons.open_in_new_rounded,
  'language': Icons.language_rounded,
  'folder': Icons.folder_rounded,
  'lock': Icons.lock_rounded,
  'power': Icons.power_settings_new_rounded,
  'sports_motorsports': Icons.sports_motorsports_rounded,
  'sports_esports': Icons.sports_esports_rounded,
  'flag': Icons.flag_rounded,
  'speed': Icons.speed_rounded,
  'fuel': Icons.local_gas_station_rounded,
  'tyre': Icons.tire_repair_rounded,
  'lightbulb': Icons.lightbulb_rounded,
  'key': Icons.key_rounded,
  'bolt': Icons.bolt_rounded,
  'visibility_off': Icons.visibility_off_rounded,
  'memory': Icons.memory_rounded,
  'developer_board': Icons.developer_board_rounded,
  'thermostat': Icons.thermostat_rounded,
  'timer': Icons.timer_rounded,
  'star': Icons.star_rounded,
  'home': Icons.home_rounded,
};

IconData buttonIcon(DeckButton button) =>
    deckIcons[button.icon] ?? _autoIcon(button.action);

Color buttonColor(DeckButton button) =>
    deckColors[button.color] ?? _autoColor(button.action);

/// The color a reading has wherever it shows: CPU blue, GPU teal, and so on.
Color statColor(String stat) => switch (stat) {
  'cpuLoad' => deckColors['blue']!,
  'gpuLoad' => deckColors['teal']!,
  'ramLoad' => deckColors['purple']!,
  'fps' => deckColors['green']!,
  'lapTime' || 'lastLap' || 'bestLap' => deckColors['purple']!,
  _ when stat.endsWith('Temp') => deckColors['amber']!,
  _ => deckColors['red']!,
};

IconData _autoIcon(ButtonAction action) => switch (action) {
  MediaAction(media: 'playPause') => Icons.play_arrow_rounded,
  MediaAction(media: 'next') => Icons.skip_next_rounded,
  MediaAction(media: 'previous') => Icons.skip_previous_rounded,
  MediaAction(media: 'volumeUp') => Icons.volume_up_rounded,
  MediaAction(media: 'volumeDown') => Icons.volume_down_rounded,
  MediaAction(media: 'mute') => Icons.volume_off_rounded,
  MediaAction() => Icons.music_note_rounded,
  KeysAction() => Icons.keyboard_rounded,
  OpenAction(:final target) when target.contains('://') =>
    Icons.language_rounded,
  OpenAction() => Icons.open_in_new_rounded,
  StatAction(:final stat) => switch (stat) {
    'cpuLoad' || 'cpuTemp' => Icons.memory_rounded,
    'gpuLoad' || 'gpuTemp' => Icons.developer_board_rounded,
    'fps' => Icons.speed_rounded,
    'fuel' => Icons.local_gas_station_rounded,
    _ => Icons.sports_motorsports_rounded,
  },
};

Color _autoColor(ButtonAction action) => switch (action) {
  MediaAction() => deckColors['teal']!,
  KeysAction() => deckColors['blue']!,
  OpenAction() => deckColors['purple']!,
  StatAction(:final stat) => statColor(stat),
};

/// A guess at a page's icon from its name, for the page rail.
IconData pageIcon(String name) {
  final words = name.toLowerCase();
  if (words.contains('main') || words.contains('home')) {
    return Icons.home_rounded;
  }
  if (words.contains('pc') || words.contains('stat')) {
    return Icons.memory_rounded;
  }
  if (words.contains('rac') || words.contains('sim') || words.contains('ac')) {
    return Icons.sports_motorsports_rounded;
  }
  if (words.contains('discord') || words.contains('voice')) {
    return Icons.headset_mic_rounded;
  }
  if (words.contains('music') || words.contains('spotify')) {
    return Icons.music_note_rounded;
  }
  return Icons.grid_view_rounded;
}

final deckTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: DeckLook.background,
  colorScheme: ColorScheme.fromSeed(
    seedColor: deckColors['blue']!,
    brightness: Brightness.dark,
    primary: deckColors['blue'],
    surface: DeckLook.background,
    onSurface: DeckLook.text,
    surfaceContainerHighest: DeckLook.cardBorder,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: DeckLook.background,
    surfaceTintColor: Colors.transparent,
  ),
  dialogTheme: const DialogThemeData(backgroundColor: DeckLook.card),
  cardTheme: CardThemeData(
    color: DeckLook.card,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(DeckLook.radius),
      side: const BorderSide(color: DeckLook.cardBorder),
    ),
  ),
);
