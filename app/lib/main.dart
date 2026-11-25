import 'dart:async';
import 'dart:math';

import 'package:deskpilot/agent_connection.dart';
import 'package:deskpilot/deck.dart';
import 'package:deskpilot/deck_view.dart';
import 'package:deskpilot/look.dart';
import 'package:deskpilot/now_playing.dart';
import 'package:deskpilot/pairing.dart';
import 'package:deskpilot/scan_page.dart';
import 'package:deskpilot/settings.dart';
import 'package:deskpilot/settings_page.dart';
import 'package:deskpilot/tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const DeskPilotApp());

const _telemetryTimeout = Duration(seconds: 2);

class DeskPilotApp extends StatefulWidget {
  const DeskPilotApp({
    super.key,
    this.store = const PcStore(),
    this.settingsStore = const SettingsStore(),
  });

  final PcStore store;
  final SettingsStore settingsStore;

  @override
  State<DeskPilotApp> createState() => _DeskPilotAppState();
}

class _DeskPilotAppState extends State<DeskPilotApp> {
  AppSettings _settings = const AppSettings();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final settings = await widget.settingsStore.load();
    if (!mounted) return;
    setState(() => _settings = settings);
    unawaited(applyScreen(settings));
  }

  void _change(AppSettings settings) {
    setState(() => _settings = settings);
    unawaited(widget.settingsStore.save(settings));
    unawaited(applyScreen(settings));
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DeskPilot',
    theme: deckTheme(
      theme: _settings.theme,
      spacing: _settings.spacing,
      corners: _settings.corners,
    ),
    home: DeckPage(
      store: widget.store,
      settings: _settings,
      onSettings: _change,
    ),
  );
}

class DeckPage extends StatefulWidget {
  const DeckPage({
    super.key,
    required this.store,
    this.settings = const AppSettings(),
    this.onSettings,
  });

  final PcStore store;
  final AppSettings settings;
  final ValueChanged<AppSettings>? onSettings;

  @override
  State<DeckPage> createState() => _DeckPageState();
}

class _DeckPageState extends State<DeckPage> {
  SavedPc? _saved;
  AgentConnection? _agent;
  Deck? _deck;
  Map<String, double> _stats = const {};
  Map<String, double> _telemetry = const {};
  DateTime _telemetryAt = DateTime(0);
  Map<String, List<double>> _history = const {};
  NowPlaying? _media;
  String? _folder;
  // Pictures from the PC by id, and the ids already asked for.
  Map<String, Uint8List> _pictures = const {};
  Set<String> _askedPictures = const {};
  int _page = 0;
  bool _editing = false;
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
      connected.events().listen(
        (event) => _onEvent(connected, event),
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

  void _onEvent(AgentConnection from, AgentEvent event) {
    if (!mounted || _agent != from) return;
    setState(() {
      switch (event) {
        case DeckChanged(:final deck):
          _deck = deck;
          _askForPictures(from, deck);
        case PictureArrived(:final id, :final bytes?):
          _pictures = {..._pictures, id: bytes};
        case PictureArrived():
          break; // the PC doesn't have it; the button shows its icon
        case StatsChanged(:final stats):
          // Telemetry stops when you leave the track; don't keep showing the last lap.
          if (DateTime.now().difference(_telemetryAt) > _telemetryTimeout) {
            _telemetry = const {};
          }
          _stats = stats;
          _history = _withReadings(_history, {...stats, ..._telemetry});
        case MediaChanged(:final media):
          _media = media?.withCoverFrom(_media);
        case TelemetryChanged(:final telemetry):
          _telemetry = telemetry;
          _telemetryAt = DateTime.now();
        case PcSays(:final text):
          _status = text;
      }
    });
  }

  /// Asks the PC once for each picture the deck uses that the phone hasn't
  /// got yet.
  void _askForPictures(AgentConnection agent, Deck deck) {
    final missing = deck.pictureIds.difference({
      ..._pictures.keys,
      ..._askedPictures,
    });
    if (missing.isEmpty) return;
    _askedPictures = {..._askedPictures, ...missing};
    missing.forEach(agent.getImage);
  }

  /// Keeps a picked photo here and on the PC, and returns its id.
  String _savePicture(Uint8List bytes) {
    final id = pictureId(bytes);
    setState(() => _pictures = {..._pictures, id: bytes});
    _agent?.saveImage(id, bytes);
    return id;
  }

  void _save(Deck deck) {
    final agent = _agent;
    if (agent == null) {
      _show('Connect to the PC to save changes.');
      return;
    }
    agent.saveDeck(deck);
  }

  Future<void> _forget() async {
    _attempt++;
    final agent = _agent;
    setState(() {
      _agent = null;
      _saved = null;
      _deck = null;
      _stats = const {};
      _telemetry = const {};
      _history = const {};
      _media = null;
      _folder = null;
      _pictures = const {};
      _askedPictures = const {};
      _page = 0;
      _editing = false;
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
      _stats = const {};
      _telemetry = const {};
      _media = null;
      // Ask again after reconnecting for any picture that hadn't arrived.
      _askedPictures = const {};
      _status = 'Lost the connection to ${agent.pcName}';
    });
  }

  @override
  void dispose() {
    unawaited(_agent?.close());
    super.dispose();
  }

  /// The vibration and click a press gives, as settings say.
  void _feedback() {
    if (widget.settings.haptics) unawaited(HapticFeedback.lightImpact());
    if (widget.settings.clickSound) {
      unawaited(SystemSound.play(SystemSoundType.click));
    }
  }

  void _press(String id) {
    _feedback();
    _agent?.press(id);
  }

  void _mediaKey(String key) {
    _feedback();
    _agent?.mediaKey(key);
  }

  Future<void> _openSettings() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SettingsPage(
        settings: widget.settings,
        onChanged: (settings) => widget.onSettings?.call(settings),
        pcName: _saved?.pc.name,
        onForget: () => unawaited(_forget()),
      ),
    ),
  );

  /// Full screen hides the top bar on tablets; its buttons move to the rail.
  bool _barHidden(BuildContext context) =>
      widget.settings.fullScreen &&
      _saved != null &&
      MediaQuery.sizeOf(context).width >= 600;

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    return Scaffold(
      appBar: _barHidden(context)
          ? null
          : AppBar(
              title: const Text('DeskPilot'),
              actions: [
                if (saved != null && _deck != null)
                  IconButton(
                    onPressed: () => setState(() => _editing = !_editing),
                    tooltip: _editing ? 'Done editing' : 'Edit the deck',
                    icon: Icon(_editing ? Icons.check : Icons.edit),
                  ),
                IconButton(
                  onPressed: _openSettings,
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_rounded),
                ),
              ],
            ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
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

  Widget _deckView() {
    final deck = _deck;
    final agent = _agent;
    final media = _media;
    final page = deck == null ? 0 : min(_page, deck.pages.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Full screen keeps quiet while all is well.
        if (agent == null || !widget.settings.fullScreen)
          Text(_status, textAlign: TextAlign.center),
        if (agent == null && !_busy) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _signIn,
            child: const Text('Connect again'),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: deck == null
              ? const SizedBox.shrink()
              : DeckView(
                  deck: deck,
                  page: page,
                  editing: _editing,
                  onPress: agent == null ? null : _press,
                  onChange: _save,
                  onPageChanged: (page) => setState(() {
                    _page = page;
                    _folder = null;
                  }),
                  folder: _folder,
                  pictures: _pictures,
                  onPicture: agent == null ? null : _savePicture,
                  onFolderChanged: (id) => setState(() => _folder = id),
                  stats: {..._stats, ..._telemetry},
                  history: _history,
                  header: _homeCards(page, media, agent),
                  tools: _barHidden(context)
                      ? [
                          (
                            icon: _editing
                                ? Icons.check_rounded
                                : Icons.edit_rounded,
                            label: _editing ? 'Done' : 'Edit',
                            onTap: () => setState(() => _editing = !_editing),
                          ),
                          (
                            icon: Icons.settings_rounded,
                            label: 'Settings',
                            onTap: () => unawaited(_openSettings()),
                          ),
                        ]
                      : const [],
                ),
        ),
      ],
    );
  }
}

/// The home screen cards above the buttons: the song and the PC, and the big
/// PC rings, as settings say. Null when there are none on this page.
extension on _DeckPageState {
  Widget? _homeCards(int page, NowPlaying? media, AgentConnection? agent) {
    final settings = widget.settings;
    if (_editing ||
        _folder != null ||
        (page != 0 && !settings.cardsOnEveryPage)) {
      return null;
    }
    final top = [
      if (settings.showMusic && media != null)
        Expanded(
          child: NowPlayingCard(
            media: media,
            onKey: agent == null ? null : _mediaKey,
          ),
        ),
      if (settings.showClock) _PcCard(name: agent?.pcName, stats: _stats),
    ];
    final rows = [
      if (top.isNotEmpty)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: top,
          ),
        ),
      if (settings.bigPcCards)
        SizedBox(
          height: 150,
          child: Row(
            spacing: 10,
            children: [
              for (final (stat, label) in [
                ('cpuLoad', 'CPU'),
                ('gpuLoad', 'GPU'),
                ('ramLoad', 'RAM'),
                ('fps', 'FPS'),
              ])
                Expanded(
                  child: StatTile(
                    label: label,
                    action: StatAction(stat, 'gauge'),
                    value: _stats[stat],
                    maximum: statMaximum(stat),
                    history: const [],
                    color: statColor(stat),
                  ),
                ),
            ],
          ),
        ),
    ];
    if (rows.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: rows,
    );
  }
}

/// The clock, which PC this is, and its CPU temperature and FPS, beside the
/// music card.
class _PcCard extends StatelessWidget {
  const _PcCard({required this.name, required this.stats});

  /// Null while the PC isn't connected.
  final String? name;
  final Map<String, double> stats;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // 10:28 PM or 22:28, as the phone is set.
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(now),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final (cpuTemp, fps) = (stats['cpuTemp'], stats['fps']);
    final pc = name;
    return Card(
      child: SizedBox(
        width: 170,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                time,
                style: TextStyle(
                  color: DeckLook.of(context).text,
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${_days[now.weekday - 1]} ${now.day} ${_months[now.month - 1]}',
                style: TextStyle(
                  color: DeckLook.of(context).muted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                spacing: 6,
                children: [
                  Icon(
                    Icons.circle,
                    size: 8,
                    color: pc == null
                        ? DeckLook.of(context).muted
                        : deckColors['green'],
                  ),
                  Expanded(
                    child: Text(
                      pc ?? 'Not connected',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: DeckLook.of(context).text,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              if (cpuTemp != null || fps != null)
                Text.rich(
                  TextSpan(
                    children: [
                      if (cpuTemp != null)
                        TextSpan(
                          text: formatStat('cpuTemp', cpuTemp),
                          style: TextStyle(color: deckColors['amber']),
                        ),
                      if (cpuTemp != null && fps != null)
                        const TextSpan(text: '  ·  '),
                      if (fps != null)
                        TextSpan(
                          text: '${formatStat('fps', fps)} fps',
                          style: TextStyle(color: deckColors['green']),
                        ),
                    ],
                  ),
                  style: TextStyle(
                    color: DeckLook.of(context).muted,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Adds the newest readings to the last minute of each one, for chart tiles.
Map<String, List<double>> _withReadings(
  Map<String, List<double>> history,
  Map<String, double> stats,
) => {
  for (final MapEntry(:key, :value) in stats.entries)
    key: List.unmodifiable([
      ...(history[key] ?? const <double>[]).skip(
        max(0, (history[key]?.length ?? 0) - (statHistoryLength - 1)),
      ),
      value,
    ]),
};
