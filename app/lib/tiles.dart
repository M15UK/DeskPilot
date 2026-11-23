import 'dart:math';

import 'package:deskpilot/deck.dart';
import 'package:deskpilot/look.dart';
import 'package:flutter/material.dart';

/// How many readings a chart tile shows: one a second for a minute.
const statHistoryLength = 60;

/// How a reading looks on a tile: 41°C, 24%, or a dash when the PC can't
/// tell.
String formatStat(String stat, double? value) => switch ((stat, value)) {
  (_, null) => '—',
  ('gear', final double gear) =>
    gear < 0 ? 'R' : (gear == 0 ? 'N' : '${gear.round()}'),
  ('lapTime' || 'lastLap' || 'bestLap', final double seconds) => _lapTime(
    seconds,
  ),
  ('position', final double position) => 'P${position.round()}',
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
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String? style;
  final String? show;
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
            child: LayoutBuilder(
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
                            fontSize: (side * (show == 'name' ? 0.14 : 0.08))
                                .clamp(12, 28)
                                .toDouble(),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
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
        color: DeckLook.of(context).text,
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
