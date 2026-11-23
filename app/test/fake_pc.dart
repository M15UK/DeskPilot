import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Replies a pretend PC sends after the phone's first message.
typedef Answer = List<Map<String, Object>> Function(Object? firstMessage);

/// A pretend DeskPilot PC with its own self signed certificate.
class FakePc {
  FakePc._(this._server, this.fingerprint, Answer answer) {
    _server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      var first = true;
      socket.listen((message) {
        final json = jsonDecode(message as String);
        _count++;
        _received.add(json);
        if (first) {
          first = false;
          for (final reply in answer(json)) {
            socket.add(jsonEncode(reply));
          }
        }
      });
    });
  }

  final HttpServer _server;
  final String fingerprint;
  final _received = StreamController<Object?>();
  late final _messages = StreamIterator(_received.stream);
  int _count = 0;

  int get port => _server.port;

  /// How many messages the phone has sent so far.
  int get receivedCount => _count;

  static Future<FakePc> start(Answer answer) async {
    final (:cert, :key) = await _makeCertificate();
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(cert))
      ..usePrivateKeyBytes(utf8.encode(key));
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    return FakePc._(server, _fingerprintOf(cert), answer);
  }

  Future<Object?> nextMessage() async {
    if (!await _messages.moveNext().timeout(const Duration(seconds: 5))) {
      throw StateError('The phone closed the connection');
    }
    return _messages.current;
  }

  Future<void> stop() async {
    await _server.close(force: true);
    // Not awaited: a paused reader never sees the close, so it would wait forever.
    unawaited(_received.close());
  }

  // Made fresh with openssl for each test, so no private key lives in the repo.
  static Future<({String cert, String key})> _makeCertificate() async {
    final folder = await Directory.systemTemp.createTemp('fake-pc-');
    try {
      final result = await Process.run('openssl', [
        'req', '-x509', '-newkey', 'rsa:2048', '-nodes', //
        '-keyout', '${folder.path}/key.pem',
        '-out', '${folder.path}/cert.pem',
        '-days', '30', '-subj', '/CN=FakePC',
      ]);
      if (result.exitCode != 0) {
        throw StateError('openssl failed: ${result.stderr}');
      }
      return (
        cert: await File('${folder.path}/cert.pem').readAsString(),
        key: await File('${folder.path}/key.pem').readAsString(),
      );
    } finally {
      await folder.delete(recursive: true);
    }
  }

  static String _fingerprintOf(String pem) {
    final body = pem
        .split('\n')
        .where((line) => line.isNotEmpty && !line.startsWith('-----'))
        .join();
    return sha256.convert(base64Decode(body)).toString();
  }
}
