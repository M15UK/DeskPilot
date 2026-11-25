import 'package:deskpilot/deck.dart';
import 'package:flutter/material.dart';

/// DeskPilot's look: a dark screen, slightly lighter cards, one accent
/// color, and how round and far apart things are. Read it with [of]; the
/// themes in [deckLooks] are picked in settings.
@immutable
class DeckLook extends ThemeExtension<DeckLook> {
  const DeckLook({
    required this.name,
    required this.background,
    required this.rail,
    required this.card,
    required this.cardBorder,
    required this.text,
    required this.muted,
    required this.accent,
    this.radius = 28,
    this.gap = 10,
  });

  final String name;
  final Color background;
  final Color rail;
  final Color card;
  final Color cardBorder;
  final Color text;
  final Color muted;
  final Color accent;
  final double radius;
  final double gap;

  static DeckLook of(BuildContext context) =>
      Theme.of(context).extension<DeckLook>() ?? deckLooks['midnight']!;

  @override
  DeckLook copyWith({double? radius, double? gap}) => DeckLook(
    name: name,
    background: background,
    rail: rail,
    card: card,
    cardBorder: cardBorder,
    text: text,
    muted: muted,
    accent: accent,
    radius: radius ?? this.radius,
    gap: gap ?? this.gap,
  );

  @override
  DeckLook lerp(DeckLook? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

/// The themes, by the name settings save.
const deckLooks = {
  'midnight': DeckLook(
    name: 'Midnight',
    background: Color(0xFF0B0D12),
    rail: Color(0xFF0F1218),
    card: Color(0xFF161A22),
    cardBorder: Color(0xFF222736),
    text: Color(0xFFEDEFF5),
    muted: Color(0xFF8A90A2),
    accent: Color(0xFF4C8DFF),
  ),
  'carbon': DeckLook(
    name: 'Carbon',
    background: Color(0xFF0D0D0D),
    rail: Color(0xFF131313),
    card: Color(0xFF1A1A1A),
    cardBorder: Color(0xFF2A2A2A),
    text: Color(0xFFF2F2F2),
    muted: Color(0xFF999999),
    accent: Color(0xFF2BD4B4),
  ),
  'neon': DeckLook(
    name: 'Neon',
    background: Color(0xFF0D0A16),
    rail: Color(0xFF120E1F),
    card: Color(0xFF1A1430),
    cardBorder: Color(0xFF2C2350),
    text: Color(0xFFF3EEFF),
    muted: Color(0xFF9C92B8),
    accent: Color(0xFFFF6FB1),
  ),
  'racing': DeckLook(
    name: 'Racing red',
    background: Color(0xFF0F0A0A),
    rail: Color(0xFF160E0E),
    card: Color(0xFF1F1414),
    cardBorder: Color(0xFF3A2020),
    text: Color(0xFFF5ECEC),
    muted: Color(0xFFA89090),
    accent: Color(0xFFFF5A5F),
  ),
};

/// Gaps between buttons, by the name settings save.
const deckSpacings = {'tight': 6.0, 'normal': 10.0, 'roomy': 16.0};

/// How round corners are, by the name settings save.
// Far apart on purpose, so each choice looks clearly different on a tablet.
const deckCorners = {'square': 2.0, 'soft': 12.0, 'round': 28.0};

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
  FolderAction() => Icons.folder_rounded,
  MusicAction() => Icons.music_note_rounded,
  ClockAction() => Icons.schedule_rounded,
  PhotosAction() => Icons.photo_library_rounded,
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
  FolderAction() => deckColors['amber']!,
  MusicAction() => deckColors['pink']!,
  ClockAction() => deckColors['blue']!,
  PhotosAction() => deckColors['purple']!,
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

/// The app's theme for a look, spacing and corners from settings.
ThemeData deckTheme({
  String theme = 'midnight',
  String spacing = 'normal',
  String corners = 'round',
}) {
  final look = (deckLooks[theme] ?? deckLooks['midnight']!).copyWith(
    gap: deckSpacings[spacing],
    radius: deckCorners[corners],
  );
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: look.background,
    extensions: [look],
    colorScheme: ColorScheme.fromSeed(
      seedColor: look.accent,
      brightness: Brightness.dark,
      primary: look.accent,
      surface: look.background,
      onSurface: look.text,
      surfaceContainerHighest: look.cardBorder,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: look.background,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(backgroundColor: look.card),
    cardTheme: CardThemeData(
      color: look.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(look.radius),
        side: BorderSide(color: look.cardBorder),
      ),
    ),
  );
}
