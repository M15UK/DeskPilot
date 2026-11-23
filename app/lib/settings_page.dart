import 'package:deskpilot/look.dart';
import 'package:deskpilot/settings.dart';
import 'package:flutter/material.dart';

/// This phone's settings: the paired PC, the look, the screen, feedback on
/// presses, and the home screen cards. Each change is saved right away.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.pcName,
    required this.onForget,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;

  /// Null when no PC is paired.
  final String? pcName;
  final VoidCallback onForget;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late AppSettings _settings = widget.settings;

  void _change(AppSettings settings) {
    setState(() => _settings = settings);
    widget.onChanged(settings);
  }

  Future<void> _forget() async {
    final name = widget.pcName ?? 'this PC';
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Forget $name?'),
        content: const Text(
          "You'll need to scan the QR code on the PC again to connect.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    Navigator.of(context).pop();
    widget.onForget();
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    final look = DeckLook.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _Section('Your PC'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.computer_rounded),
            title: Text(widget.pcName ?? 'No PC paired'),
            trailing: widget.pcName == null
                ? null
                : OutlinedButton(
                    onPressed: _forget,
                    child: const Text('Forget this PC'),
                  ),
          ),
          _Section('Look'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final MapEntry(:key, :value) in deckLooks.entries)
                _ThemeChoice(
                  look: value,
                  selected: s.theme == key,
                  onTap: () => _change(s.copyWith(theme: key)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _Choice(
            title: 'Spacing',
            choices: const {
              'tight': 'Tight',
              'normal': 'Normal',
              'roomy': 'Roomy',
            },
            selected: s.spacing,
            onSelect: (spacing) => _change(s.copyWith(spacing: spacing)),
          ),
          const SizedBox(height: 12),
          _Choice(
            title: 'Corners',
            choices: const {
              'square': 'Square',
              'soft': 'Soft',
              'round': 'Round',
            },
            selected: s.corners,
            onSelect: (corners) => _change(s.copyWith(corners: corners)),
          ),
          _Section('Screen'),
          _Switch(
            title: 'Full screen',
            subtitle:
                "Hides the top bar and Android's bars. Swipe from an "
                'edge to see them for a moment.',
            value: s.fullScreen,
            onChanged: (on) => _change(s.copyWith(fullScreen: on)),
          ),
          _Switch(
            title: 'Keep the screen on',
            subtitle: 'While DeskPilot is open, for example during a race.',
            value: s.keepScreenOn,
            onChanged: (on) => _change(s.copyWith(keepScreenOn: on)),
          ),
          _Section('Presses'),
          _Switch(
            title: 'Vibrate',
            subtitle: 'A small buzz each time you press a button.',
            value: s.haptics,
            onChanged: (on) => _change(s.copyWith(haptics: on)),
          ),
          _Switch(
            title: 'Click sound',
            subtitle: 'Uses the tablet\'s own click, at its system volume.',
            value: s.clickSound,
            onChanged: (on) => _change(s.copyWith(clickSound: on)),
          ),
          _Section('Home screen'),
          _Switch(
            title: 'Music card',
            subtitle: 'The song playing on the PC, with its cover.',
            value: s.showMusic,
            onChanged: (on) => _change(s.copyWith(showMusic: on)),
          ),
          _Switch(
            title: 'Clock and PC card',
            value: s.showClock,
            onChanged: (on) => _change(s.copyWith(showClock: on)),
          ),
          _Switch(
            title: 'Big PC cards',
            subtitle: 'CPU, GPU, RAM and FPS as large rings.',
            value: s.bigPcCards,
            onChanged: (on) => _change(s.copyWith(bigPcCards: on)),
          ),
          _Switch(
            title: 'Show them on every page',
            subtitle: 'Otherwise they only show on the first page.',
            value: s.cardsOnEveryPage,
            onChanged: (on) => _change(s.copyWith(cardsOnEveryPage: on)),
          ),
          const SizedBox(height: 8),
          Text(
            'These settings are for this tablet only. Your buttons and pages '
            'are kept on the PC.',
            style: TextStyle(color: look.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(
      title,
      style: TextStyle(
        color: DeckLook.of(context).accent,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = subtitle;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: text == null ? null : Text(text),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.choices,
    required this.selected,
    required this.onSelect,
  });

  final String title;
  final Map<String, String> choices;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 16,
    children: [
      SizedBox(width: 80, child: Text(title)),
      Expanded(
        child: SegmentedButton<String>(
          segments: [
            for (final MapEntry(:key, :value) in choices.entries)
              ButtonSegment(value: key, label: Text(value)),
          ],
          selected: {selected},
          onSelectionChanged: (picked) => onSelect(picked.single),
        ),
      ),
    ],
  );
}

/// A small preview of a theme: its screen, a card and its accent color.
class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.look,
    required this.selected,
    required this.onTap,
  });

  final DeckLook look;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: look.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? look.accent : look.cardBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Row(
              spacing: 6,
              children: [
                for (final color in [look.card, look.accent, look.muted])
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: look.cardBorder),
                    ),
                  ),
              ],
            ),
            Text(look.name, style: TextStyle(color: look.text)),
          ],
        ),
      ),
    ),
  );
}
