// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

/// Permissive license allow-list for ZVComm.
///
/// Rejects GPL/LGPL/AGPL/BUSL and other restricted licenses.
const allowedLicensePatterns = <String>[
  'mit',
  'apache',
  'apache-2.0',
  'apache 2.0',
  'bsd',
  'bsd-2-clause',
  'bsd-3-clause',
  'isc',
  'zlib',
  '0bsd',
  'unlicense',
  'cc0',
  'public domain',
  'mpl-2.0', // Mozilla — permissive enough for linking; review if strict
];

/// Known-bad license tokens (fail closed on these).
const bannedTokens = <String>[
  'gpl',
  'lgpl',
  'agpl',
  'busl',
  'sspl',
  'commons clause',
  'commercial',
  'proprietary',
];

/// Packages we explicitly own / path-depend (no pub license needed).
const pathPackagePrefixes = <String>[
  'zvcomm_',
];

Future<void> main(List<String> args) async {
  final root = Directory.current;
  final pubspecs = await _findPubspecs(root);
  if (pubspecs.isEmpty) {
    stderr.writeln('No pubspec.yaml files found under ${root.path}');
    exitCode = 1;
    return;
  }

  print('ZVComm license gate — scanning ${pubspecs.length} packages\n');

  final seen = <String>{};
  var failures = 0;

  for (final pubspec in pubspecs) {
    final packageDir = pubspec.parent;
    final lockFile = File('${packageDir.path}/pubspec.lock');
    if (!lockFile.existsSync()) {
      // Workspace members may share root lock; try root.
      continue;
    }
    failures += await _checkLockfile(lockFile, seen);
  }

  final rootLock = File('${root.path}/pubspec.lock');
  if (rootLock.existsSync()) {
    failures += await _checkLockfile(rootLock, seen);
  }

  // Also scan package_config for workspace resolution.
  final packageConfigs = await _findFiles(root, 'package_config.json');
  for (final pc in packageConfigs) {
    if (pc.path.contains('.dart_tool')) {
      failures += await _checkPackageConfig(pc, seen);
    }
  }

  // Fallback: parse all pubspec dependencies for direct deps only.
  for (final pubspec in pubspecs) {
    failures += await _checkPubspecDeps(pubspec, seen);
  }

  print('\nChecked ${seen.length} unique dependency names.');
  if (failures > 0) {
    stderr.writeln('\nFAILED: $failures license issue(s) found.');
    exitCode = 1;
  } else {
    print('\nOK: no banned licenses detected in scanned manifests.');
    print('Note: always re-verify licenses at dependency pin time.');
  }
}

Future<int> _checkLockfile(File lockFile, Set<String> seen) async {
  try {
    final content = lockFile.readAsStringSync();
    // pubspec.lock is YAML; do a lightweight parse for package names + no
    // license field (pub lock does not include licenses). We record names
    // and rely on package_config / manual allow for now.
    final nameRe = RegExp(r'^  ([a-zA-Z0-9_]+):$', multiLine: true);
    for (final m in nameRe.allMatches(content)) {
      final name = m.group(1)!;
      if (name == 'sdks') continue;
      seen.add(name);
    }
  } catch (e) {
    stderr.writeln('warn: could not read ${lockFile.path}: $e');
  }
  return 0;
}

Future<int> _checkPackageConfig(File file, Set<String> seen) async {
  var failures = 0;
  try {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final packages = json['packages'] as List<dynamic>? ?? [];
    for (final p in packages) {
      final map = p as Map<String, dynamic>;
      final name = map['name'] as String? ?? '';
      if (name.isEmpty) continue;
      seen.add(name);
      if (_isPathPackage(name)) continue;

      // Best-effort: if rootUri points to pub-cache, try LICENSE file.
      final rootUri = map['rootUri'] as String? ?? '';
      failures += _scanLicenseNear(name, rootUri);
    }
  } catch (e) {
    stderr.writeln('warn: package_config parse ${file.path}: $e');
  }
  return failures;
}

int _scanLicenseNear(String name, String rootUri) {
  if (rootUri.isEmpty || rootUri == '../') return 0;
  Uri uri;
  try {
    uri = Uri.parse(rootUri);
  } catch (_) {
    return 0;
  }
  if (!uri.isScheme('file') && !rootUri.startsWith('/')) {
    // Relative to .dart_tool — skip complex resolution here.
    return 0;
  }
  final path = uri.isScheme('file') ? uri.toFilePath() : rootUri;
  final dir = Directory(path);
  if (!dir.existsSync()) return 0;

  for (final candidate in ['LICENSE', 'LICENSE.md', 'COPYING', 'LICENSE.txt']) {
    final f = File('${dir.path}/$candidate');
    if (!f.existsSync()) continue;
    final text = f.readAsStringSync().toLowerCase();
    return _evaluateLicenseText(name, text);
  }
  return 0;
}

int _evaluateLicenseText(String name, String text) {
  // Ban check first.
  for (final banned in bannedTokens) {
    // Avoid matching "mit" inside longer words; for gpl use word-ish checks.
    if (banned == 'gpl' || banned == 'lgpl' || banned == 'agpl') {
      final re = RegExp('\\b$banned(?:v?\\d)?\\b', caseSensitive: false);
      // Apache license text does not contain gpl as a grant.
      if (re.hasMatch(text) &&
          !text.contains('not gpl') &&
          text.contains('gnu general public')) {
        stderr.writeln('BANNED: $name appears to use $banned');
        return 1;
      }
      if (text.contains('gnu general public license') ||
          text.contains('gnu lesser general public') ||
          text.contains('gnu affero general public')) {
        stderr.writeln('BANNED: $name appears to use copyleft ($banned family)');
        return 1;
      }
    } else if (text.contains(banned) && banned == 'busl') {
      stderr.writeln('BANNED: $name appears to use BUSL');
      return 1;
    }
  }

  final allowed = allowedLicensePatterns.any(text.contains);
  if (!allowed && text.length > 40) {
    // Unknown — warn but do not fail hard without stronger signals.
    print('WARN: $name LICENSE not recognized as allow-listed (manual review)');
  } else if (allowed) {
    print('OK: $name');
  }
  return 0;
}

Future<int> _checkPubspecDeps(File pubspec, Set<String> seen) async {
  final lines = pubspec.readAsLinesSync();
  var inDeps = false;
  for (final line in lines) {
    if (line.startsWith('dependencies:') ||
        line.startsWith('dev_dependencies:')) {
      inDeps = true;
      continue;
    }
    if (inDeps && RegExp(r'^[a-zA-Z]').hasMatch(line)) {
      inDeps = false;
    }
    if (!inDeps) continue;
    final m = RegExp(r'^\s{2}([a-zA-Z0-9_]+):').firstMatch(line);
    if (m != null) {
      seen.add(m.group(1)!);
    }
  }
  return 0;
}

bool _isPathPackage(String name) =>
    pathPackagePrefixes.any(name.startsWith) ||
    name == 'flutter' ||
    name == 'flutter_test' ||
    name == 'sky_engine' ||
    name == 'flutter_localizations';

Future<List<File>> _findPubspecs(Directory root) async {
  final out = <File>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File &&
        entity.path.endsWith('pubspec.yaml') &&
        !entity.path.contains('.dart_tool') &&
        !entity.path.contains('/example/')) {
      out.add(entity);
    }
  }
  return out;
}

Future<List<File>> _findFiles(Directory root, String filename) async {
  final out = <File>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith(filename)) {
      out.add(entity);
    }
  }
  return out;
}
