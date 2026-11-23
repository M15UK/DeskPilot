import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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

  /// What the PC says from now on, as text for the status line.
  /// Listen once; it ends when the connection closes.
  Stream<String> statuses() async* {
    while (await _messages.moveNext()) {
      final message = _messages.current;
      if (message is String) yield describe(message);
    }
  }

  void playPause() =>
      _socket.add(jsonEncode({'type': 'media', 'action': 'playPause'}));

  Future<void> close() => _socket.close();
}

/// Turns one message from the PC into text for the status line.
String describe(String message) {
  final Object? json;
  try {
    json = jsonDecode(message);
  } on FormatException {
    return 'Unexpected message from the PC';
  }
  return switch (json) {
    {'type': 'hello', 'name': final String name} => 'Connected to $name',
    {'type': 'error', 'message': final String text} => text,
    _ => 'Unexpected message from the PC',
  };
}
