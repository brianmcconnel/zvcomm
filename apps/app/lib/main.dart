import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ui/ui.dart';

import 'screens/home_shell.dart';
import 'services/mesh_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZvcommApp());
}

class ZvcommApp extends StatelessWidget {
  const ZvcommApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZVComm',
      debugShowCheckedModeBanner: false,
      theme: ZvcommTheme.light(),
      darkTheme: ZvcommTheme.dark(),
      themeMode: ThemeMode.system,
      home: const _Bootstrap(),
    );
  }
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      builder: (context, _) => HomeShell(mesh: _mesh),
    );
  }
}
