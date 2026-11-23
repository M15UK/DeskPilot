import 'dart:async';

import 'package:deskpilot/agent_connection.dart';
import 'package:deskpilot/pairing.dart';
import 'package:deskpilot/scan_page.dart';
import 'package:flutter/material.dart';

void main() => runApp(const DeskPilotApp());

class DeskPilotApp extends StatelessWidget {
  const DeskPilotApp({super.key, this.store = const PcStore()});

  final PcStore store;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DeskPilot',
    theme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
    ),
    home: DeckPage(store: store),
  );
}

class DeckPage extends StatefulWidget {
  const DeckPage({super.key, required this.store});

  final PcStore store;

  @override
  State<DeckPage> createState() => _DeckPageState();
}

class _DeckPageState extends State<DeckPage> {
  SavedPc? _saved;
  AgentConnection? _agent;
  bool _loading = true;
  bool _busy = false;
  String _status = '';
  // Counts connection attempts, so a slow one that ends after Forget is
  // thrown away.
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedPc());
  }

  Future<void> _loadSavedPc() async {
    final saved = await widget.store.load();
    if (!mounted) return;
    setState(() {
      _saved = saved;
      _loading = false;
    });
    await _signIn();
  }

  Future<void> _signIn() async {
    final saved = _saved;
    if (saved == null) return;
    await _open(saved.pc, () => AgentConnection.signIn(saved));
  }

  Future<void> _scanAndPair() async {
    final text = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ScanPage()));
    if (text == null || !mounted) return;
    final qr = readPairingQr(text);
    if (qr == null) {
      _show("That QR code isn't from DeskPilot. Scan the one on your PC.");
      return;
    }
    await _open(qr.pc, () => AgentConnection.pair(qr));
  }

  Future<void> _open(
    PcInfo pc,
    Future<AgentConnection> Function() connect,
  ) async {
    final attempt = ++_attempt;
    setState(() {
      _busy = true;
      _status = 'Connecting to ${pc.name}…';
    });
    AgentConnection? agent;
    try {
      agent = await connect();
      final saved = (pc: pc, key: agent.key);
      await widget.store.save(saved);
      if (!mounted || attempt != _attempt) {
        unawaited(agent.close());
        return;
      }
      final connected = agent;
      connected.statuses().listen(
        _show,
        onError: (Object _) => _lost(connected),
        onDone: () => _lost(connected),
      );
      setState(() {
        _saved = saved;
        _agent = connected;
        _status = 'Connected to ${connected.pcName}';
      });
    } on AgentRefused catch (refused) {
      _show(refused.message);
    } on Exception {
      unawaited(agent?.close());
      _show("Couldn't connect to ${pc.name}. Try again.");
    } finally {
      if (mounted && attempt == _attempt) setState(() => _busy = false);
    }
  }

  Future<void> _forget() async {
    _attempt++;
    final agent = _agent;
    setState(() {
      _agent = null;
      _saved = null;
      _busy = false;
      _status = '';
    });
    await agent?.close();
    await widget.store.clear();
  }

  void _show(String status) {
    if (mounted) setState(() => _status = status);
  }

  void _lost(AgentConnection agent) {
    if (!mounted || _agent != agent) return;
    setState(() {
      _agent = null;
      _status = 'Lost the connection to ${agent.pcName}';
    });
  }

  @override
  void dispose() {
    unawaited(_agent?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    return Scaffold(
      appBar: AppBar(
        title: const Text('DeskPilot'),
        actions: [
          if (saved != null)
            IconButton(
              onPressed: _forget,
              tooltip: 'Forget this PC',
              icon: const Icon(Icons.link_off),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : saved == null
              ? _pairView(context)
              : _deckView(),
        ),
      ),
    );
  }

  Widget _pairView(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(Icons.qr_code_scanner, size: 96),
      const SizedBox(height: 16),
      Text(
        'Pair with your PC',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text(
        'Start DeskPilot on your PC. A QR code opens there. Scan it here.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: _busy ? null : _scanAndPair,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scan the QR code'),
      ),
      const SizedBox(height: 16),
      Text(_status, textAlign: TextAlign.center),
    ],
  );

  Widget _deckView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(_status, textAlign: TextAlign.center),
      if (_agent == null && !_busy) ...[
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _signIn, child: const Text('Connect again')),
      ],
      const Spacer(),
      SizedBox(
        height: 160,
        child: FilledButton.icon(
          onPressed: _agent?.playPause,
          icon: const Icon(Icons.play_arrow_rounded, size: 48),
          label: const Text('Play / Pause', style: TextStyle(fontSize: 24)),
        ),
      ),
      const Spacer(),
    ],
  );
}
