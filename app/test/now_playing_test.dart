import 'dart:convert';

import 'package:deskpilot/agent_connection.dart';
import 'package:deskpilot/now_playing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _at = DateTime(2026, 11, 23, 21, 42);

NowPlaying song({
  bool playing = true,
  double? position = 30,
  double? duration = 240,
  String? coverId = 'c1',
  List<int>? cover = const [1, 2, 3],
}) => NowPlaying.fromJson({
  'title': 'Neon Highway',
  'artist': 'The Midnight Drive',
  'app': 'Spotify',
  'playing': playing,
  'position': ?position,
  'duration': ?duration,
  'coverId': ?coverId,
  if (cover != null) 'cover': base64Encode(cover),
}, _at)!;

void main() {
  test('reads the song and its cover from the PC', () {
    final event = readEvent(
      '{"type":"media","media":{"title":"Neon Highway","artist":"The Midnight Drive",'
      '"app":"Spotify","playing":true,"position":30,"duration":240,"coverId":"c1","cover":"AQID"}}',
    );

    final media = (event as MediaChanged).media!;
    expect(media.title, 'Neon Highway');
    expect(media.app, 'Spotify');
    expect(media.cover, [1, 2, 3]);
  });

  test('nothing playing hides the card', () {
    expect((readEvent('{"type":"media"}') as MediaChanged).media, isNull);
  });

  test('a song sent without its cover keeps the picture the phone has', () {
    final paused = song(playing: false, cover: null).withCoverFrom(song());

    expect(paused.cover, [1, 2, 3]);
    expect(
      song(coverId: 'c2', cover: null).withCoverFrom(song()).cover,
      isNull,
    );
  });

  test('a playing song moves on between messages, a paused one does not', () {
    final later = _at.add(const Duration(seconds: 5));

    expect(song().positionAt(later), 35);
    expect(song(playing: false).positionAt(later), 30);
    expect(song(position: 238).positionAt(later), 240);
    expect(song(duration: null, position: null).positionAt(later), isNull);
  });

  testWidgets('the music card shows the song and presses media keys', (
    tester,
  ) async {
    String? pressed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NowPlayingCard(media: song(), onKey: (key) => pressed = key),
        ),
      ),
    );

    expect(find.text('Neon Highway'), findsOneWidget);
    expect(find.text('The Midnight Drive'), findsOneWidget);
    await tester.tap(find.byTooltip('Next'));
    expect(pressed, 'next');
    await tester.tap(find.byTooltip('Pause'));
    expect(pressed, 'playPause');
  });
}
