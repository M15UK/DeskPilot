import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _protocolVersion = 4;
final _fingerprintPattern = RegExp(r'^[0-9a-f]{64}$');

/// A PC running DeskPilot, as its pairing QR code describes it.
/// See docs/PROTOCOL.md.
class PcInfo {
  const PcInfo({
    required this.name,
    required this.hosts,
    required this.port,
    required this.fingerprint,
  });

  final String name;

  /// IP addresses to try, in order.
  final List<String> hosts;
  final int port;

  /// SHA-256 of the PC's certificate, as 64 lowercase hex characters.
  /// The app talks only to a PC that shows exactly this certificate.
  final String fingerprint;

  Map<String, Object> toJson() => {
    'name': name,
    'hosts': hosts,
    'port': port,
    'fingerprint': fingerprint,
  };

  static PcInfo? fromJson(Object? json) => switch (json) {
    {
      'name': final String name,
      'hosts': final List<Object?> hosts,
      'port': final int port,
      'fingerprint': final String fingerprint,
    }
        when hosts.isNotEmpty &&
            hosts.every(_isIpAddress) &&
            port > 0 &&
            port < 65536 &&
            _fingerprintPattern.hasMatch(fingerprint) =>
      PcInfo(
        name: name,
        hosts: List.unmodifiable(hosts.cast<String>()),
        port: port,
        fingerprint: fingerprint,
      ),
    _ => null,
  };
}

bool _isIpAddress(Object? host) =>
    host is String && InternetAddress.tryParse(host) != null;

/// What a pairing QR code holds: the PC and a one time code.
typedef PairingQr = ({PcInfo pc, String code});

/// A paired PC and the key this phone signs in with.
typedef SavedPc = ({PcInfo pc, String key});

/// Reads a scanned QR code, or returns null when it isn't a DeskPilot one.
PairingQr? readPairingQr(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (json case {'deskpilot': _protocolVersion, 'code': final String code}
      when code.isNotEmpty) {
    if (PcInfo.fromJson(json) case final PcInfo pc) return (pc: pc, code: code);
  }
  return null;
}

/// Keeps the paired PC and its key in the phone's secure storage
/// (Android Keystore, iPhone Keychain).
class PcStore {
  const PcStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;
  static const _storageKey = 'pc';

  Future<SavedPc?> load() async {
    final text = await _storage.read(key: _storageKey);
    if (text == null) return null;
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json case {'pc': final Object? pc, 'key': final String key}) {
      if (PcInfo.fromJson(pc) case final PcInfo info) {
        return (pc: info, key: key);
      }
    }
    return null;
  }

  Future<void> save(SavedPc saved) => _storage.write(
    key: _storageKey,
    value: jsonEncode({'pc': saved.pc.toJson(), 'key': saved.key}),
  );

  Future<void> clear() => _storage.delete(key: _storageKey);
}
