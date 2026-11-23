import 'dart:convert';
import 'dart:typed_data';

import 'package:deskpilot/look.dart';
import 'package:flutter/material.dart';

/// The song the PC is playing. Times are in seconds. [cover] is the album
/// art; the PC sends each picture once, and later messages only carry its
/// [coverId] (see [withCoverFrom]).
class NowPlaying {
  const NowPlaying({
    required this.title,
    required this.artist,
    required this.app,
    required this.playing,
    required this.receivedAt,
    this.position,
    this.duration,
    this.coverId,
    this.cover,
  });

  final String title;
  final String artist;
  final String app;
  final bool playing;
  final DateTime receivedAt;
  final double? position;
  final double? duration;
  final String? coverId;
  final Uint8List? cover;

  /// Reads the PC's `media` message. Null when nothing is playing.
  static NowPlaying? fromJson(Object? json, DateTime receivedAt) {
    if (json
        case {
          'title': final String title,
          'artist': final String artist,
          'app': final String app,
          'playing': final bool playing,
        }
        when title.isNotEmpty) {
      final map = json as Map<String, Object?>;
      return NowPlaying(
        title: title,
        artist: artist,
        app: app,
        playing: playing,
        receivedAt: receivedAt,
        position: _number(map['position']),
        duration: _number(map['duration']),
        coverId: switch (map['coverId']) {
          final String id => id,
          _ => null,
        },
        cover: _picture(map['cover']),
      );
    }
    return null;
  }

  /// This song with [previous]'s picture when the PC left it out because the
  /// phone already has it.
  NowPlaying withCoverFrom(NowPlaying? previous) =>
      cover != null || coverId == null || previous?.coverId != coverId
      ? this
      : NowPlaying(
          title: title,
          artist: artist,
          app: app,
          playing: playing,
          receivedAt: receivedAt,
          position: position,
          duration: duration,
          coverId: coverId,
          cover: previous?.cover,
        );

  /// Where the song is at [now]: it moves on while playing, up to its end.
  double? positionAt(DateTime now) {
    final (at, end) = (position, duration);
    if (at == null || end == null) return null;
    final moved = playing
        ? now.difference(receivedAt).inMilliseconds / 1000
        : 0.0;
    return (at + moved).clamp(0, end).toDouble();
  }
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

Uint8List? _picture(Object? base64) {
  if (base64 is! String) return null;
  try {
    return base64Decode(base64);
  } on FormatException {
    return null;
  }
}

/// 3:07, for song times.
String _clock(double seconds) {
  final whole = seconds.floor();
  return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}';
}

/// The music card: cover art, title, artist, progress and controls. The
/// buttons are off while [onKey] is null (the PC isn't connected).
class NowPlayingCard extends StatelessWidget {
  const NowPlayingCard({super.key, required this.media, required this.onKey});

  final NowPlaying media;
  final ValueChanged<String>? onKey;

  static const _tint = Color(0xFF15213A);
  static const _soft = Color(0xFFB7C3DB);
  static const _faint = Color(0xFF8FA3C8);

  @override
  Widget build(BuildContext context) {
    final position = media.positionAt(DateTime.now());
    final duration = media.duration;
    final key = onKey;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _tint,
        borderRadius: BorderRadius.circular(DeckLook.radius),
        border: Border.all(color: const Color(0xFF22325A)),
      ),
      child: Row(
        spacing: 14,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox.square(
              dimension: 112,
              child: switch (media.cover) {
                final Uint8List cover => Image.memory(
                  cover,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  semanticLabel: 'Album cover',
                  errorBuilder: (_, _, _) => const _NoCover(),
                ),
                null => const _NoCover(),
              },
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Playing on your PC, ${media.app}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _faint, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  media.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: DeckLook.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  media.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _soft, fontSize: 13),
                ),
                if (position != null && duration != null && duration > 0) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: position / duration,
                      minHeight: 4,
                      color: DeckLook.text,
                      backgroundColor: const Color(0xFF2A3A5E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  DefaultTextStyle(
                    style: const TextStyle(color: _faint, fontSize: 11),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_clock(position)),
                        Text(_clock(duration)),
                      ],
                    ),
                  ),
                ],
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous',
                      color: _soft,
                      onPressed: key == null ? null : () => key('previous'),
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    IconButton.filled(
                      tooltip: media.playing ? 'Pause' : 'Play',
                      style: IconButton.styleFrom(
                        backgroundColor: DeckLook.text,
                        foregroundColor: _tint,
                      ),
                      onPressed: key == null ? null : () => key('playPause'),
                      icon: Icon(
                        media.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next',
                      color: _soft,
                      onPressed: key == null ? null : () => key('next'),
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoCover extends StatelessWidget {
  const _NoCover();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xFF1B2F55),
    child: Icon(Icons.music_note_rounded, size: 40, color: Color(0xFF8FA3C8)),
  );
}
