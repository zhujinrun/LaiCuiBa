// Checks that the active toolchain matches the versions pinned for LaiCuiBa.
//
// The original app ships Flutter 3.44.9 / Dart 3.12.2 (framework revision
// 6b182d2). Building with a different SDK changes text layout, Material 3
// component metrics and Impeller rendering, so the pixel comparisons in
// `.probe/` stop being valid. This script fails loudly instead of letting a
// silent mismatch rot the UI.
//
// Usage:  dart run tool/verify_toolchain.dart
// Exit:   0 on match, 1 on mismatch.

import 'dart:convert';
import 'dart:io';

const _expectedFlutter = '3.44.9';
const _expectedDart = '3.12.2';

Future<void> main() async {
  final problems = <String>[];

  final dartVersion = Platform.version.split(' ').first;
  if (dartVersion != _expectedDart) {
    problems.add('Dart: expected $_expectedDart, got $dartVersion');
  }

  final flutterVersion = await _flutterVersion();
  if (flutterVersion == null) {
    problems.add('Flutter: could not determine the active version');
  } else if (flutterVersion != _expectedFlutter) {
    problems.add('Flutter: expected $_expectedFlutter, got $flutterVersion');
  }

  if (problems.isEmpty) {
    stdout.writeln('toolchain ok: Flutter $_expectedFlutter / Dart $_expectedDart');
    return;
  }

  stderr
    ..writeln('toolchain mismatch:')
    ..writeln(problems.map((p) => '  - $p').join('\n'))
    ..writeln('')
    ..writeln('The project is pinned to Flutter $_expectedFlutter (see .fvmrc).')
    ..writeln('Switch the SDK for this checkout, e.g. with fvm:')
    ..writeln('  fvm install $_expectedFlutter && fvm use $_expectedFlutter');
  exitCode = 1;
}

/// Official Flutter releases report `flutterVersion` in --machine output,
/// while the locally pinned checkout reports `frameworkVersion`. Accept both,
/// and fall back to plain `flutter --version` text if --machine is unavailable.
Future<String?> _flutterVersion() async {
  final executable = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final runInShell = Platform.isWindows;

  try {
    final result = await Process.run(
      executable,
      const ['--version', '--machine'],
      runInShell: runInShell,
    );
    if (result.exitCode == 0) {
      final decoded =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final version = decoded['flutterVersion'] ?? decoded['frameworkVersion'];
      if (version != null) return version.toString();
    }
  } on ProcessException {
    // Fall through to the text form.
  } on FormatException {
    // Fall through to the text form.
  }

  try {
    final result = await Process.run(
      executable,
      const ['--version'],
      runInShell: runInShell,
    );
    if (result.exitCode != 0) return null;
    final match = RegExp(r'Flutter\s+(\d+\.\d+\.\d+)').firstMatch(
      result.stdout as String,
    );
    return match?.group(1);
  } on ProcessException {
    return null;
  }
}
