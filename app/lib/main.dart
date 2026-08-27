import 'package:flutter/material.dart';

import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';

const _gitCommit = String.fromEnvironment('GIT_COMMIT', defaultValue: 'local');
const _buildNumber = String.fromEnvironment('BUILD_NUMBER', defaultValue: 'local');
const _channel = String.fromEnvironment('CHANNEL', defaultValue: 'local');

void main() {
  runApp(const TunesApp());
}

class TunesApp extends StatelessWidget {
  const TunesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MaterialApp(
      title: 'tunes',
      debugShowCheckedModeBanner: false,
      theme: buildTunesTheme(mq),
      home: const LibraryHome(),
    );
  }
}

class LibraryHome extends StatefulWidget {
  const LibraryHome({super.key});

  @override
  State<LibraryHome> createState() => _LibraryHomeState();
}

class _LibraryHomeState extends State<LibraryHome> {
  int _tab = 0;

  static const _tabs = ['Tracks', 'Albums', 'Artists', 'Channels'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('tunes', style: TypeScale.wordmark),
                  const SizedBox(height: Space.xs),
                  Text('codename — library', style: TypeScale.caption),
                ],
              ),
            ),
            Expanded(
              child: Center(child: _EmptyLibrary(label: _tabs[_tab])),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
              child: const BuildVitals(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.library_music_outlined), label: 'Tracks'),
          NavigationDestination(icon: Icon(Icons.album_outlined), label: 'Albums'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'Artists'),
          NavigationDestination(icon: Icon(Icons.send_outlined), label: 'Channels'),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Tones.surfaceRaised,
              borderRadius: BorderRadius.circular(RadiusTokens.control),
            ),
            child: const Icon(Icons.music_note_outlined, size: 32, color: Tones.textMuted),
          ),
          const SizedBox(height: Space.lg),
          Text('No $label yet', style: TypeScale.title),
          const SizedBox(height: Space.sm),
          Text(
            'Point tunesd at your channels and your library will '
            'appear here — tagged, deduped, and ranked.',
            textAlign: TextAlign.center,
            style: TypeScale.body,
          ),
        ],
      ),
    );
  }
}

class BuildVitals extends StatelessWidget {
  const BuildVitals({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      '$_channel · $_gitCommit · $_buildNumber',
      style: TypeScale.caption,
    );
  }
}