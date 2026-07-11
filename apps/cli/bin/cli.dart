import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:core/core.dart';
import 'package:pki/pki.dart';
import 'package:sim/sim.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage')
    ..addCommand(
      'identity',
      ArgParser()
        ..addOption('name',
            abbr: 'n', defaultsTo: 'device', help: 'Display name')
        ..addOption('seed', abbr: 's', help: 'Deterministic seed (tests only)')
        ..addOption('out', help: 'Write identity JSON (includes private keys)'),
    )
    ..addCommand(
      'ca-init',
      ArgParser()
        ..addOption('name', defaultsTo: 'ZVComm Root')
        ..addOption('out', defaultsTo: 'ca-identity.json'),
    )
    ..addCommand(
      'ca-issue',
      ArgParser()
        ..addOption('ca', help: 'CA identity JSON path')
        ..addOption('subject-seed', defaultsTo: 'device')
        ..addOption('name', defaultsTo: 'device')
        ..addOption('days', defaultsTo: '30')
        ..addOption('out', help: 'Write certificate JSON'),
    )
    ..addCommand(
      'enroll',
      ArgParser()
        ..addOption('seed', defaultsTo: 'device')
        ..addOption('name', defaultsTo: 'device')
        ..addOption('ca', help: 'CA identity JSON (issues immediately)')
        ..addOption('out-req', help: 'Write enrollment request JSON')
        ..addOption('out-cert', help: 'Write issued certificate JSON'),
    )
    ..addCommand(
      'noise-demo',
      ArgParser()
        ..addOption('alice-seed', defaultsTo: 'alice')
        ..addOption('bob-seed', defaultsTo: 'bob'),
    )
    ..addCommand(
      'sim',
      ArgParser()
        ..addOption(
          'topology',
          defaultsTo: 'line',
          allowed: ['line', 'grid', 'random', 'bridge'],
        )
        ..addOption('nodes', defaultsTo: '5')
        ..addOption('rows', defaultsTo: '4')
        ..addOption('cols', defaultsTo: '4')
        ..addOption('spacing', defaultsTo: '20')
        ..addOption('range', defaultsTo: '40')
        ..addOption('loss', defaultsTo: '0')
        ..addFlag('mobility', defaultsTo: false)
        ..addFlag('presence', defaultsTo: false)
        ..addOption('broadcasts', defaultsTo: '1'),
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
      stdout.writeln('zvcomm 0.5.0 (Phase 3)');
    case 'identity':
      await _cmdIdentity(results.command!);
    case 'ca-init':
      await _cmdCaInit(results.command!);
    case 'ca-issue':
      await _cmdCaIssue(results.command!);
    case 'enroll':
      await _cmdEnroll(results.command!);
    case 'noise-demo':
      await _cmdNoiseDemo(results.command!);
    case 'sim':
      await _cmdSim(results.command!);
    default:
      _usage(parser);
      exitCode = 64;
  }
}

void _usage(ArgParser parser) {
  stdout.writeln('''
ZVComm CLI — PKI, secure sessions, mesh simulator

Commands:
  identity    Generate X25519/Ed25519 device identity
  ca-init     Create a root CA identity file
  ca-issue    Issue an Ed25519 mesh certificate
  enroll      Create enrollment request (and optionally issue)
  noise-demo  Run initiator/responder handshake + AEAD round-trip
  sim         Mesh simulation
  version

${parser.usage}
''');
}

Future<void> _cmdIdentity(ArgResults cmd) async {
  final name = cmd['name'] as String;
  final seed = cmd['seed'] as String?;
  final id = seed != null
      ? await DeviceIdentity.fromSeed(seed, displayName: name)
      : await DeviceIdentity.generate(displayName: name);
  final json = id.toJson(includePrivate: cmd['out'] != null);
  final text = const JsonEncoder.withIndent('  ').convert(json);
  stdout.writeln(text);
  final out = cmd['out'] as String?;
  if (out != null) {
    await File(out).writeAsString(text);
  }
}

Future<void> _cmdCaInit(ArgResults cmd) async {
  final ca = await LocalCa.generate(displayName: cmd['name'] as String);
  final path = cmd['out'] as String;
  final store = FileIdentityStore.path(path);
  await store.save(StoredIdentity(identity: ca.root));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'caId': ca.root.id,
    'displayName': ca.root.displayName,
    'path': path,
  }));
}

Future<DeviceIdentity> _loadIdentity(String path) async {
  final store = FileIdentityStore.path(path);
  final stored = await store.load();
  if (stored == null) {
    throw StateError('identity not found: $path');
  }
  return stored.identity;
}

Future<void> _cmdCaIssue(ArgResults cmd) async {
  final LocalCa ca;
  final caPath = cmd['ca'] as String?;
  if (caPath != null) {
    ca = LocalCa(root: await _loadIdentity(caPath));
  } else {
    ca = await LocalCa.generate(displayName: 'ZVComm Root');
  }
  final subject = await DeviceIdentity.fromSeed(
    cmd['subject-seed'] as String,
    displayName: cmd['name'] as String,
  );
  final days = int.parse(cmd['days'] as String);
  final cert = await ca.issueFor(subject, ttl: Duration(days: days));
  final payload = {
    'caId': ca.root.id,
    'certificate': cert.toJson(),
    'verified': await ca.verify(cert),
  };
  final text = const JsonEncoder.withIndent('  ').convert(payload);
  stdout.writeln(text);
  final out = cmd['out'] as String?;
  if (out != null) {
    await File(out).writeAsString(
      const JsonEncoder.withIndent('  ').convert(cert.toJson()),
    );
  }
}

Future<void> _cmdEnroll(ArgResults cmd) async {
  final device = await DeviceIdentity.fromSeed(
    cmd['seed'] as String,
    displayName: cmd['name'] as String,
  );
  final req = await EnrollmentService.createRequest(device);
  final reqJson = const JsonEncoder.withIndent('  ').convert(req.toJson());
  final outReq = cmd['out-req'] as String?;
  if (outReq != null) {
    await File(outReq).writeAsString(reqJson);
  } else {
    stdout.writeln(reqJson);
  }

  final caPath = cmd['ca'] as String?;
  if (caPath == null) return;

  final ca = LocalCa(root: await _loadIdentity(caPath));
  final svc = EnrollmentService(ca);
  final resp = await svc.processRequest(req);
  final cert = MeshCertificate.fromJsonString(resp.certificateJson);
  final outCert = cmd['out-cert'] as String?;
  final certText = const JsonEncoder.withIndent('  ').convert(cert.toJson());
  if (outCert != null) {
    await File(outCert).writeAsString(certText);
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'enrolled': true,
    'subjectId': cert.subjectId,
    'verified': await ca.verify(cert),
  }));
}

Future<void> _cmdNoiseDemo(ArgResults cmd) async {
  final alice = await DeviceIdentity.fromSeed(cmd['alice-seed'] as String,
      displayName: 'Alice');
  final bob = await DeviceIdentity.fromSeed(cmd['bob-seed'] as String,
      displayName: 'Bob');

  final hsA = Handshake(alice);
  final init = await hsA.createInitiation();
  final accepted = await Handshake(bob).acceptInitiation(init);
  final sessionA = await hsA.finish(accepted.response);
  final sessionB = accepted.session;

  final cipher =
      await sessionA.seal(Uint8List.fromList(utf8.encode('hello secure mesh')));
  final clear = await sessionB.open(cipher);

  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'aliceId': alice.id,
    'bobId': bob.id,
    'handshakeInitBytes': init.length,
    'handshakeRespBytes': accepted.response.length,
    'cipherBytes': cipher.length,
    'plaintext': utf8.decode(clear),
    'ok': utf8.decode(clear) == 'hello secure mesh',
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
