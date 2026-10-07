import 'dart:async';

import 'package:fl_pinned_shortcuts/fl_pinned_shortcuts.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterPinnedShortcuts.initialize();
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  StreamSubscription<Map<String, dynamic>>? _shortcutSubscription;
  bool _supported = false;
  bool _assetPinned = false;
  bool _networkPinned = false;
  String _lastClick = 'No shortcut clicked yet.';

  @override
  void initState() {
    super.initState();
    _listenForShortcutClicks();
    _refreshSupport();
    _refreshPinnedStates();
  }

  void _listenForShortcutClicks() {
    _shortcutSubscription =
        FlutterPinnedShortcuts.onShortcutClick.listen((data) {
      setState(() {
        _lastClick = 'id: ${data['id']}\nextraData: ${data['extraData']}';
      });
    });
  }

  Future<void> _refreshSupport() async {
    final supported = await FlutterPinnedShortcuts.isSupported();
    if (!mounted) return;
    setState(() => _supported = supported);
  }

  Future<void> _refreshPinnedStates() async {
    final assetPinned =
        await FlutterPinnedShortcuts.isPinned('asset_shortcut');
    final networkPinned =
        await FlutterPinnedShortcuts.isPinned('network_shortcut');
    if (!mounted) return;
    setState(() {
      _assetPinned = assetPinned;
      _networkPinned = networkPinned;
    });
  }

  Future<void> _createAssetShortcut() async {
    await FlutterPinnedShortcuts.createPinnedShortcut(
      id: 'asset_shortcut',
      label: 'My Shortcut',
      imageSource: 'assets/shortcut.png',
      imageSourceType: ImageSourceType.asset,
      adaptiveIconForeground: 'assets/shortcut.png',
      adaptiveIconBackground: '#2196F3',
      adaptiveIconBackgroundType: AdaptiveIconBackgroundType.color,
      longLabel: 'My Flutter Asset Shortcut',
      extraData: const {'source': 'asset'},
    );
    await _refreshPinnedStates();
  }

  Future<void> _createNetworkShortcut() async {
    await FlutterPinnedShortcuts.createPinnedShortcut(
      id: 'network_shortcut',
      label: 'Network Shortcut',
      imageSource: 'https://picsum.photos/256',
      imageSourceType: ImageSourceType.network,
      longLabel: 'Network image using DefaultCacheManager',
      extraData: const {'source': 'network'},
    );
    await _refreshPinnedStates();
  }

  @override
  void dispose() {
    _shortcutSubscription?.cancel();
    FlutterPinnedShortcuts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Pinned shortcuts')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              _supported
                  ? 'Pinned shortcuts are supported.'
                  : 'Pinned shortcuts are not supported.',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _supported ? _createAssetShortcut : null,
              icon: const Icon(Icons.push_pin_outlined),
              label: Text(
                _assetPinned ? 'Asset shortcut is pinned' : 'Pin asset shortcut',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _supported ? _createNetworkShortcut : null,
              icon: const Icon(Icons.cloud_outlined),
              label: Text(
                _networkPinned
                    ? 'Network shortcut is pinned'
                    : 'Pin network shortcut',
              ),
            ),
            const SizedBox(height: 24),
            const Text('Last shortcut click'),
            const SizedBox(height: 8),
            SelectableText(_lastClick),
          ],
        ),
      ),
    );
  }
}
