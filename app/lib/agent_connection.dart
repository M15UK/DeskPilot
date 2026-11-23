import 'dart:convert';
import 'dart:io';

/// Port the PC agent listens on. Must match AgentServer.DefaultPort.
const agentPort = 8740;

const _connectTimeout = Duration(seconds: 5);

/// A live connection to DeskPilot on a PC. See docs/PROTOCOL.md.
class AgentConnection {
  AgentConnection._(this._socket);

  final WebSocket _socket;

  /// Opens a connection, or throws an [Exception] when the PC can't be reached.
  // shortcut: plain ws:// with no pairing, Phase 2 adds QR pairing and TLS.
  static Future<AgentConnection> connect(
    String host, {
    int port = agentPort,
  }) async {
    final uri = Uri(scheme: 'ws', host: host, port: port, path: '/ws');
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final socket = await WebSocket.connect(
        uri.toString(),
        customClient: client,
      );
      return AgentConnection._(socket);
    } finally {
      client.close();
    }
  }

  /// What the PC says, as text for the status line. Listen once; it ends
  /// when the connection closes.
  late final Stream<String> statuses = _socket
      .where((message) => message is String)
      .cast<String>()
      .map(describe);

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
