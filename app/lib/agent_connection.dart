import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:deskpilot/deck.dart';
import 'package:deskpilot/now_playing.dart';
import 'package:deskpilot/pairing.dart';

const _connectTimeout = Duration(seconds: 3);
const _replyTimeout = Duration(seconds: 5);

/// The PC said no, or could not be reached. [message] is meant for the user.
class AgentRefused implements Exception {
  const AgentRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A signed in, encrypted connection to DeskPilot on a PC.
/// The messages are described in docs/PROTOCOL.md.
class AgentConnection {
  AgentConnection._(this._socket, this._messages, this.pcName, this.key);

  final WebSocket _socket;
  final StreamIterator<dynamic> _messages;
  final String pcName;

  /// The key this phone signs in with. After pairing it is new: save it.
  final String key;

  /// Pairs with the PC using the one time code from its QR code.
  static Future<AgentConnection> pair(PairingQr qr) =>
      _open(qr.pc, {'type': 'pair', 'code': qr.code});

  /// Signs in to a PC this phone paired with before.
  static Future<AgentConnection> signIn(SavedPc saved) =>
      _open(saved.pc, {'type': 'auth', 'key': saved.key}, key: saved.key);

  static Future<AgentConnection> _open(
    PcInfo pc,
    Map<String, String> firstMessage, {
    String? key,
  }) async {
    final socket = await _reach(pc);
    final messages = StreamIterator<dynamic>(socket);
    try {
      socket.add(jsonEncode(firstMessage));
      var reply = await _next(messages);
      if (reply case {'type': 'paired', 'key': final String newKey}) {
        key = newKey;
        reply = await _next(messages);
      }
      return switch (reply) {
        {'type': 'hello', 'name': final String name} when key != null =>
          AgentConnection._(socket, messages, name, key),
        {'type': 'error', 'message': final String message} =>
          throw AgentRefused(message),
        _ => throw const AgentRefused('The PC sent something unexpected.'),
      };
    } on Exception {
      unawaited(socket.close());
      rethrow;
    }
  }

  /// Tries USB first (127.0.0.1 through adb reverse), then each address of
  /// the PC.
  static Future<WebSocket> _reach(PcInfo pc) async {
    for (final host in ['127.0.0.1', ...pc.hosts]) {
      try {
        return await _connect(host, pc);
      } on Exception {
        // Not at this address, or not the right PC. Try the next one.
      }
    }
    throw AgentRefused(
      "Couldn't reach ${pc.name}. Check that DeskPilot is running on it "
      'and that both are on the same network.',
    );
  }

  static Future<WebSocket> _connect(String host, PcInfo pc) {
    // No public certificate authority is trusted: only the PC's own
    // certificate, checked by its fingerprint.
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = _connectTimeout
      ..badCertificateCallback = (certificate, _, _) =>
          sha256.convert(certificate.der).toString() == pc.fingerprint;
    final uri = Uri(scheme: 'wss', host: host, port: pc.port, path: '/ws');
    return WebSocket.connect(
      uri.toString(),
      customClient: client,
    ).whenComplete(client.close);
  }

  static Future<Object?> _next(StreamIterator<dynamic> messages) async {
    if (!await messages.moveNext().timeout(_replyTimeout)) {
      throw const AgentRefused('The PC closed the connection.');
    }
    final message = messages.current;
    if (message is! String) return null;
    try {
      return jsonDecode(message);
    } on FormatException {
      return null;
    }
  }

  /// What the PC sends from now on: the deck first, then any changes and
  /// messages. Listen once; it ends when the connection closes.
  Stream<AgentEvent> events() async* {
    while (await _messages.moveNext()) {
      final message = _messages.current;
      if (message is String) yield readEvent(message);
    }
  }

  /// Runs the deck button with this id on the PC.
  void press(String id) => _send({'type': 'press', 'id': id});

  /// Asks the PC to keep this deck. It checks it and sends it to every phone.
  /// Presses a media key on the PC, for the music card's buttons.
  void mediaKey(String media) => _send({'type': 'mediaKey', 'media': media});

  void saveDeck(Deck deck) =>
      _send({'type': 'saveDeck', 'deck': deck.toJson()});

  void _send(Map<String, Object> message) => _socket.add(jsonEncode(message));

  Future<void> close() => _socket.close();
}

/// Something the PC sent after signing in.
sealed class AgentEvent {
  const AgentEvent();
}

/// The deck, after signing in and each time it changes.
final class DeckChanged extends AgentEvent {
  const DeckChanged(this.deck);

  final Deck deck;
}

/// The PC's readings, sent each second. A reading the PC can't give is left
/// out.
final class StatsChanged extends AgentEvent {
  const StatsChanged(this.stats);

  final Map<String, double> stats;
}

/// The sim racing dashboard, about 30 times a second while you drive.
final class TelemetryChanged extends AgentEvent {
  const TelemetryChanged(this.telemetry);

  final Map<String, double> telemetry;
}

/// What the PC is playing, or null when nothing is.
final class MediaChanged extends AgentEvent {
  const MediaChanged(this.media);

  final NowPlaying? media;
}

/// A message for the user, usually why something didn't work.
final class PcSays extends AgentEvent {
  const PcSays(this.text);

  final String text;
}

AgentEvent readEvent(String message) {
  final Object? json;
  try {
    json = jsonDecode(message);
  } on FormatException {
    return const PcSays('Unexpected message from the PC');
  }
  return switch (json) {
    {'type': 'deck', 'deck': final Object? deck} => switch (Deck.fromJson(
      deck,
    )) {
      final Deck read => DeckChanged(read),
      null => const PcSays(
        "The PC sent a deck this app can't show. Update the app.",
      ),
    },
    {'type': 'stats', 'stats': final Map<String, Object?> stats} =>
      StatsChanged(_numbers(stats)),
    {'type': 'telemetry', 'telemetry': final Map<String, Object?> telemetry} =>
      TelemetryChanged(_numbers(telemetry)),
    {'type': 'media'} => MediaChanged(
      NowPlaying.fromJson(
        (json as Map<String, Object?>)['media'],
        DateTime.now(),
      ),
    ),
    {'type': 'error', 'message': final String text} => PcSays(text),
    _ => const PcSays('Unexpected message from the PC'),
  };
}

/// The readings in a message, skipping anything that isn't a number.
Map<String, double> _numbers(Map<String, Object?> readings) => {
  for (final MapEntry(:key, :value) in readings.entries)
    if (value is num) key: value.toDouble(),
};
