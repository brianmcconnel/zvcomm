import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ui/ui.dart';

import 'screens/home_shell.dart';
import 'services/mesh_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Warm color-emoji fonts early so the picker never flashes □ glyphs.
  unawaited(EmojiGlyphs.ensureReady());
  runApp(const ZvcommApp());
}

class ZvcommApp extends StatefulWidget {
  const ZvcommApp({super.key});

  @override
  State<ZvcommApp> createState() => _ZvcommAppState();
}

class _ZvcommAppState extends State<ZvcommApp> {
  final ThemeController _theme = ThemeController();
  final MeshController _mesh = MeshController();
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _mesh.bootstrap();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _mesh.dispose();
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _theme,
      builder: (context, _) {
        return MaterialApp(
          title: 'ZVComm',
          debugShowCheckedModeBanner: false,
          theme: _theme.themeData,
          // Single palette mode (ZVBible-style explicit themes), not system light/dark.
          themeMode: ThemeMode.light,
          home: _home(),
        );
      },
    );
  }

  Widget _home() {
    if (_error != null) {
      return Scaffold(
        body: Center(child: Text('Failed to start: $_error')),
      );
    }
    if (!_mesh.ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return ListenableBuilder(
      listenable: _mesh,
      builder: (context, _) => HomeShell(
        mesh: _mesh,
        themeController: _theme,
      ),
    );
  }
}
