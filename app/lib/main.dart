import 'dart:async';

import 'package:deskpilot/agent_connection.dart';
import 'package:flutter/material.dart';

void main() => runApp(const DeskPilotApp());

class DeskPilotApp extends StatelessWidget {
  const DeskPilotApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DeskPilot',
    theme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
    ),
    home: const DeckPage(),
  );
}

class DeckPage extends StatefulWidget {
  const DeckPage({super.key});

  @override
  State<DeckPage> createState() => _DeckPageState();
}

class _DeckPageState extends State<DeckPage> {
  final _address = TextEditingController();
  AgentConnection? _agent;
  bool _connecting = false;
  String _status = 'Not connected';

  Future<void> _connect() async {
    final host = _address.text.trim();
    if (_connecting) return;
    if (host.isEmpty) {
      _show("Type your PC's address first");
      return;
    }
    await _agent?.close();
    setState(() {
      _agent = null;
      _connecting = true;
      _status = 'Connecting to $host…';
    });
    try {
      final agent = await AgentConnection.connect(host);
      agent.statuses.listen(
        _show,
        onError: (Object _) => _lost(agent),
        onDone: () => _lost(agent),
      );
      if (mounted) setState(() => _agent = agent);
    } on Exception {
      _show("Couldn't reach $host. Is DeskPilot running on the PC?");
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _show(String status) {
    if (mounted) setState(() => _status = status);
  }

  void _lost(AgentConnection agent) {
    if (!mounted || _agent != agent) return;
    setState(() {
      _agent = null;
      _status = 'Disconnected';
    });
  }

  @override
  void dispose() {
    unawaited(_agent?.close());
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DeskPilot')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: 'PC address',
                hintText: '192.168.1.20',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _connect(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _connecting ? null : _connect,
              child: const Text('Connect'),
            ),
            const SizedBox(height: 16),
            Text(_status, textAlign: TextAlign.center),
            const Spacer(),
            SizedBox(
              height: 160,
              child: FilledButton.icon(
                onPressed: _agent?.playPause,
                icon: const Icon(Icons.play_arrow_rounded, size: 48),
                label: const Text(
                  'Play / Pause',
                  style: TextStyle(fontSize: 24),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    ),
  );
}
