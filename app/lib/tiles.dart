import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:deskpilot/deck.dart';
import 'package:deskpilot/look.dart';
import 'package:flutter/material.dart';

/// How many readings a chart tile shows: one a second for a minute.
const statHistoryLength = 60;

/// How a reading looks on a tile: 41°C, 24%, or a dash when the PC can't
/// tell.
const _flags = {
  0: 'None',
  1: 'Blue',
  2: 'Yellow',
  3: 'Black',
  4: 'White',
  5: 'Chequered',
  6: 'Penalty',
};

/// A reading whose color tells you something: delta green when faster and
/// red when slower, the flag in its own color, the pit limiter green when on.
/// Null keeps the usual text color.
Color? readingColor(String stat, double? value) => switch ((stat, value)) {
  ('delta', final double delta) =>
    delta < 0 ? deckColors['green'] : deckColors['red'],
  ('pitLimiter' || 'inPitLane', final double on) when on > 0 =>
    deckColors['green'],
  ('flag', final double flag) => switch (flag.round()) {
    1 => deckColors['blue'],
    2 => deckColors['amber'],
    3 || 6 => deckColors['red'],
    4 => Colors.white,
    _ => null,
  },
  _ => null,
};

String formatStat(String stat, double? value) => switch ((stat, value)) {
  (_, null) => '—',
  ('gear', final double gear) =>
    gear < 0 ? 'R' : (gear == 0 ? 'N' : '${gear.round()}'),
  ('lapTime' || 'lastLap' || 'bestLap', final double seconds) => _lapTime(
    seconds,
  ),
  ('position', final double position) => 'P${position.round()}',
  ('delta', final double delta) =>
    '${delta < 0 ? '−' : '+'}${delta.abs().toStringAsFixed(3)}',
  ('pitLimiter' || 'inPitLane', final double on) => on > 0 ? 'On' : 'Off',
  ('flag', final double flag) => _flags[flag.round()] ?? 'None',
  ('sector', final double sector) => 'S${sector.round()}',
  ('lastSector', final double seconds) => _lapTime(seconds),
  ('fuelPerLap', final double litres) => '${litres.toStringAsFixed(2)} L',
  ('lapsOfFuel', final double laps) => '${laps.toStringAsFixed(1)} laps',
  ('fuelToFinish', final double litres) => '+${litres.toStringAsFixed(1)} L',
  (final name, final double psi) when name.endsWith('Pressure') =>
    '${psi.toStringAsFixed(1)} psi',
  ('fuel', final double litres) => '${litres.toStringAsFixed(1)} L',
  (final name, final double value) when name.endsWith('Temp') =>
    '${value.round()}°C',
  (final name, final double value) when name.endsWith('Load') =>
    '${value.round()}%',
  (_, final double value) => '${value.round()}',
};

/// A lap time like a race dash shows it: 1:42.345.
String _lapTime(double seconds) {
  final milliseconds = (seconds * 1000).round();
  final rest = (milliseconds % 60000) / 1000;
  return '${milliseconds ~/ 60000}:${rest.toStringAsFixed(3).padLeft(6, '0')}';
}

/// The reading that fills a gauge or reaches the top of a chart. RPM and fuel
/// use the car's own rev limit and tank from [stats]; percent and °C use 100.
double statMaximum(String stat, [Map<String, double> stats = const {}]) =>
    switch (stat) {
      'fps' => 240,
      'rpm' => stats['rpmMax'] ?? 9000,
      'fuel' => stats['fuelMax'] ?? 100,
      'speed' => 300,
      _ when stat.startsWith('tyre') => 120,
      _ => 100,
    };

/// A button: its icon over its label in its [color]. [style] is null
/// (tinted), 'solid' or 'outline'; [show] is null (icon and name), 'icon' or
/// 'name'. Dimmed and off while [onTap] is null.
class KeyTile extends StatelessWidget {
  const KeyTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.style,
    this.show,
    this.picture,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String? style;
  final String? show;

  /// The button's own picture, shown instead of the icon.
  final Uint8List? picture;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final onColor = Color.lerp(color, Colors.black, 0.78)!;
    final (fill, edge, ink, text) = switch (style) {
      'solid' => (color, color, onColor, onColor),
      'outline' => (
        Colors.transparent,
        color,
        color,
        DeckLook.of(context).text,
      ),
      _ => (
        color.withValues(alpha: 0.14),
        color.withValues(alpha: 0.35),
        Color.lerp(color, Colors.white, 0.3)!,
        DeckLook.of(context).text,
      ),
    };
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: show == 'icon' ? label : null,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Material(
          color: fill,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DeckLook.of(context).radius),
            side: BorderSide(color: edge, width: style == 'outline' ? 1.5 : 1),
          ),
          child: InkWell(
            onTap: onTap,
            splashColor: color.withValues(alpha: 0.3),
            child: picture == null
                ? LayoutBuilder(
                    builder: (context, size) {
                      // Bigger buttons get a bigger icon and name.
                      final side = min(size.maxWidth, size.maxHeight);
                      return Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          spacing: 8,
                          children: [
                            if (show != 'name')
                              Icon(
                                icon,
                                size: (side * (show == 'icon' ? 0.42 : 0.24))
                                    .clamp(20, 120)
                                    .toDouble(),
                                color: ink,
                              ),
                            if (show != 'icon')
                              Text(
                                label,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: text,
                                  fontSize:
                                      (side * (show == 'name' ? 0.14 : 0.08))
                                          .clamp(12, 28)
                                          .toDouble(),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  )
                : _Pictured(picture: picture!, label: label, show: show),
          ),
        ),
      ),
    );
  }
}

/// A button's picture filling the tile, with its name on a dark strip.
class _Pictured extends StatelessWidget {
  const _Pictured({
    required this.picture,
    required this.label,
    required this.show,
  });

  final Uint8List picture;
  final String label;
  final String? show;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.memory(
        picture,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
      if (show != 'icon')
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            color: Colors.black.withValues(alpha: 0.55),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
    ],
  );
}

/// A PC or sim reading as a big number, a ring gauge or a chart of the last
/// minute, labelled in its [color]. Tapping it does nothing outside edit mode.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.action,
    required this.value,
    required this.maximum,
    required this.history,
    required this.color,
    this.onTap,
  });

  final String label;
  final StatAction action;
  final double? value;
  final double maximum;
  final List<double> history;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final reading = Text(
      formatStat(action.stat, value),
      style: TextStyle(
        color: readingColor(action.stat, value) ?? DeckLook.of(context).text,
        fontSize: 26,
        fontWeight: FontWeight.w600,
      ),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Expanded(
                child: switch (action.style) {
                  'gauge' => Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: CircularProgressIndicator(
                              value: ((value ?? 0) / maximum).clamp(0.0, 1.0),
                              strokeWidth: 7,
                              strokeCap: StrokeCap.round,
                              color: color,
                              backgroundColor: DeckLook.of(context).cardBorder,
                            ),
                          ),
                        ),
                        FittedBox(fit: BoxFit.scaleDown, child: reading),
                      ],
                    ),
                  ),
                  'chart' => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      reading,
                      Expanded(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _ChartPainter(history, maximum, color),
                        ),
                      ),
                    ],
                  ),
                  _ => Center(
                    child: FittedBox(fit: BoxFit.scaleDown, child: reading),
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A line of the last minute of a reading with a soft fill under it, 0 at the
/// bottom and [maximum] at the top, growing in from the right.
class _ChartPainter extends CustomPainter {
  _ChartPainter(this.points, this.maximum, this.color);

  final List<double> points;
  final double maximum;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final step = size.width / (statHistoryLength - 1);
    final line = Path();
    var firstX = 0.0;
    for (final (index, point) in points.indexed) {
      final x = size.width - (points.length - 1 - index) * step;
      final y = size.height * (1 - (point / maximum).clamp(0.0, 1.0));
      if (index == 0) {
        firstX = x;
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(firstX, size.height)
      ..close();
    canvas
      ..drawPath(fill, Paint()..color = color.withValues(alpha: 0.15))
      ..drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.points != points || old.maximum != maximum || old.color != color;
}

/// The time, which PC this is, and its CPU temperature and FPS. The time
/// grows with the tile.
class ClockTile extends StatelessWidget {
  const ClockTile({super.key, required this.pcName, required this.stats});

  /// Null while the PC isn't connected.
  final String? pcName;
  final Map<String, double> stats;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final look = DeckLook.of(context);
    final now = DateTime.now();
    // 10:28 PM or 22:28, as the phone is set.
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(now),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final (cpuTemp, fps) = (stats['cpuTemp'], stats['fps']);
    final pc = pcName;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  time,
                  style: TextStyle(
                    color: look.text,
                    fontSize: 64,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Text(
              '${_days[now.weekday - 1]} ${now.day} ${_months[now.month - 1]}',
              style: TextStyle(color: look.muted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Row(
              spacing: 6,
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: pc == null ? look.muted : deckColors['green'],
                ),
                Expanded(
                  child: Text(
                    pc ?? 'Not connected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: look.text, fontSize: 12),
                  ),
                ),
              ],
            ),
            if (cpuTemp != null || fps != null)
              Text.rich(
                TextSpan(
                  children: [
                    if (cpuTemp != null)
                      TextSpan(
                        text: formatStat('cpuTemp', cpuTemp),
                        style: TextStyle(color: deckColors['amber']),
                      ),
                    if (cpuTemp != null && fps != null)
                      const TextSpan(text: '  ·  '),
                    if (fps != null)
                      TextSpan(
                        text: '${formatStat('fps', fps)} fps',
                        style: TextStyle(color: deckColors['green']),
                      ),
                  ],
                ),
                style: TextStyle(color: look.muted, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}

/// A photo frame: shows [pictures] in turn, a new one every few seconds or
/// on a tap.
class PhotosTile extends StatefulWidget {
  const PhotosTile({super.key, required this.pictures});

  final List<Uint8List> pictures;

  @override
  State<PhotosTile> createState() => _PhotosTileState();
}

class _PhotosTileState extends State<PhotosTile> {
  static const _every = Duration(seconds: 8);
  Timer? _timer;
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(PhotosTile old) {
    super.didUpdateWidget(old);
    if (old.pictures.length != widget.pictures.length) _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Only a frame with two or more photos needs to change them.
  void _restart() {
    _timer?.cancel();
    _timer = widget.pictures.length < 2
        ? null
        : Timer.periodic(_every, (_) => _next());
  }

  void _next() {
    if (widget.pictures.isNotEmpty) setState(() => _shown++);
  }

  @override
  Widget build(BuildContext context) {
    final look = DeckLook.of(context);
    final pictures = widget.pictures;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: pictures.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Icon(Icons.photo_library_rounded, color: look.muted),
                  Text(
                    'Add photos in edit mode',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: look.muted, fontSize: 12),
                  ),
                ],
              ),
            )
          : GestureDetector(
              onTap: _next,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                child: Image.memory(
                  pictures[_shown % pictures.length],
                  key: ValueKey(_shown % pictures.length),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
    );
  }
}

/// The sim car's four tyres from above: each colored by its temperature
/// (blue cold, green right, amber hot, red too hot), with its pressure.
class TyresTile extends StatelessWidget {
  const TyresTile({super.key, required this.stats});

  final Map<String, double> stats;

  static Color _heat(double? temp) => switch (temp) {
    null => const Color(0xFF2A3040),
    < 70 => deckColors['blue']!,
    <= 95 => deckColors['green']!,
    <= 105 => deckColors['amber']!,
    _ => deckColors['red']!,
  };

  @override
  Widget build(BuildContext context) {
    final look = DeckLook.of(context);
    Widget tyre(String corner) {
      final temp = stats['tyre${corner}Temp'];
      final psi = stats['tyre${corner}Pressure'];
      final color = _heat(temp);
      final ink = Color.lerp(color, Colors.black, 0.78)!;
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(look.radius * 0.5),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  Text(
                    temp == null ? '—' : '${temp.round()}°',
                    style: TextStyle(
                      color: ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (psi != null && psi > 0)
                    Text(
                      psi.toStringAsFixed(1),
                      style: TextStyle(color: ink, fontSize: 14),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
              child: Text(
                'Tyres °C, psi',
                style: TextStyle(
                  color: deckColors['amber'],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(child: Row(children: [tyre('Fl'), tyre('Fr')])),
            Expanded(child: Row(children: [tyre('Rl'), tyre('Rr')])),
          ],
        ),
      ),
    );
  }
}
