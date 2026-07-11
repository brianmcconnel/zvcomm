import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zvcomm_core/zvcomm_core.dart';
import 'package:zvcomm_pki/zvcomm_pki.dart';
import 'package:zvcomm_sim/zvcomm_sim.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage')
    ..addCommand(
      'identity',
      ArgParser()
        ..addOption('name', abbr: 'n', defaultsTo: 'device', help: 'Display name')
        ..addOption('seed', abbr: 's', help: 'Deterministic seed (tests only)'),
    )
    ..addCommand(
      'ca-issue',
      ArgParser()
        ..addOption('subject-seed', defaultsTo: 'device', help: 'Subject seed')
        ..addOption('name', defaultsTo: 'device', help: 'Subject display name')
        ..addOption('days', defaultsTo: '30', help: 'Certificate TTL in days'),
    )
    ..addCommand(
      'sim',
      ArgParser()
        ..addOption(
          'topology',
          defaultsTo: 'line',
          allowed: ['line', 'grid', 'random', 'bridge'],
          help: 'Topology: line|grid|random|bridge',
        )
        ..addOption('nodes', defaultsTo: '5', help: 'Node count (line/random)')
        ..addOption('rows', defaultsTo: '4', help: 'Grid rows')
        ..addOption('cols', defaultsTo: '4', help: 'Grid cols')
        ..addOption('spacing', defaultsTo: '20', help: 'Node spacing')
        ..addOption('range', defaultsTo: '40', help: 'Radio range meters')
        ..addOption('loss', defaultsTo: '0', help: 'Packet loss 0..1')
        ..addFlag('mobility', defaultsTo: false, help: 'Enable random-walk mobility')
        ..addFlag('presence', defaultsTo: false, help: 'Collect presence events')
        ..addOption('broadcasts', defaultsTo: '1', help: 'Number of broadcasts'),
    )
    ..addCommand('version', ArgParser());

  ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    _usage(parser);
    exitCode = 64;
    return;
  }

  if (results['help'] == true || results.command == null) {
    _usage(parser);
    return;
  }

  switch (results.command!.name) {
    case 'version':
      stdout.writeln('zvcomm_cli 0.2.0 (Phase 2)');
    case 'identity':
      _cmdIdentity(results.command!);
    case 'ca-issue':
      _cmdCaIssue(results.command!);
    case 'sim':
      await _cmdSim(results.command!);
    default:
      _usage(parser);
      exitCode = 64;
  }
}

void _usage(ArgParser parser) {
  stdout.writeln('''
ZVComm CLI — PKI helpers and mesh simulator

Usage:
  dart run zvcomm_cli <command> [options]

Commands:
  identity   Generate a device identity (placeholder keys)
  ca-issue   Issue a placeholder mesh certificate from a local CA
  sim        Run mesh simulation (line|grid|random|bridge)
  version    Print version

${parser.usage}
''');
}

void _cmdIdentity(ArgResults cmd) {
  final name = cmd['name'] as String;
  final seed = cmd['seed'] as String?;
  final id = seed != null
      ? DeviceIdentity.fromSeed(seed, displayName: name)
      : DeviceIdentity.generate(displayName: name);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'id': id.id,
    'displayName': id.displayName,
    'publicKey': base64Url.encode(id.publicKeyBytes),
  }));
}

void _cmdCaIssue(ArgResults cmd) {
  final ca = LocalCa.generate(displayName: 'ZVComm Root');
  final subject = DeviceIdentity.fromSeed(
    cmd['subject-seed'] as String,
    displayName: cmd['name'] as String,
  );
  final days = int.parse(cmd['days'] as String);
  final cert = ca.issueFor(subject, ttl: Duration(days: days));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'caId': ca.root.id,
    'certificate': cert.toJson(),
    'verified': ca.verify(cert),
  }));
}

Future<void> _cmdSim(ArgResults cmd) async {
  final topology = cmd['topology'] as String;
  final nodes = int.parse(cmd['nodes'] as String);
  final spacing = double.parse(cmd['spacing'] as String);
  final range = double.parse(cmd['range'] as String);
  final loss = double.parse(cmd['loss'] as String);
  final mobility = cmd['mobility'] as bool;
  final presence = cmd['presence'] as bool;
  final broadcasts = int.parse(cmd['broadcasts'] as String);

  final SimScenario scenario;
  switch (topology) {
    case 'grid':
      scenario = SimScenario.grid(
        rows: int.parse(cmd['rows'] as String),
        cols: int.parse(cmd['cols'] as String),
        spacing: spacing,
        rangeMeters: range,
        packetLoss: loss,
      );
    case 'random':
      scenario = SimScenario.random(
        count: nodes,
        rangeMeters: range,
        packetLoss: loss,
        mobility: mobility,
      );
    case 'bridge':
      scenario = SimScenario.bridge(
        perCluster: (nodes / 2).floor().clamp(2, 50),
        spacing: spacing,
        rangeMeters: range,
      );
    case 'line':
    default:
      scenario = SimScenario.line(
        count: nodes,
        spacing: spacing,
        rangeMeters: range,
        packetLoss: loss,
      );
  }

  final result = await MeshSimulator().run(
    scenario,
    options: SimRunOptions(
      broadcastCount: broadcasts,
      collectPresence: presence,
      settleAfterStart: Duration(
        milliseconds: (500 + scenario.nodes.length * 10).clamp(500, 8000),
      ),
      settleAfterSend: Duration(
        milliseconds: (700 + scenario.nodes.length * 12).clamp(700, 12000),
      ),
    ),
  );
  stdout.writeln(result);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
}
