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
    problems.add('Flutter: could not run `flutter --version` (not on PATH?)');
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

Future<String?> _flutterVersion() async {
  // On Windows the SDK ships `flutter.bat`, which only resolves through a
  // shell. Using `runInShell` keeps one code path for all platforms.
  final executable = Platform.isWindows ? 'flutter.bat' : 'flutter';
  try {
    final result = await Process.run(
      executable,
      ['--version', '--machine'],
      runInShell: true,
    );
    if (result.exitCode != 0) return null;
    final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    return decoded['frameworkVersion'] as String?;
  } on ProcessException {
    return null;
  } on FormatException {
    return null;
  }
}
