import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the runtime binaries a 猫源 needs: `node.exe` and the rewritten
/// `cat_host.js`.
///
/// The binaries are not Flutter assets (node.exe is ~67 MB and must not be
/// loaded into memory); they sit beside the build output and are copied there
/// by `tool/sync_runtime.sh` before launch. Resolution order:
///
///   1. an explicit directory handed in (tests / embedding);
///   2. `<executable dir>/runtime/node/` (packaged build);
///   3. `<project root>/assets/runtime/node/` (running from source).
class RuntimePaths {
  const RuntimePaths._(this.node, this.hostScript);

  final String node;
  final String hostScript;

  /// True when both files exist, so the app can skip wiring the spider at all
  /// when the runtime has not been synced yet.
  bool get available => File(node).existsSync() && File(hostScript).existsSync();

  /// Resolves from [overrideDir] when given, else by probing the two standard
  /// locations. Returns null when neither file is present.
  static RuntimePaths? resolve({String? overrideDir, String? executableDir}) {
    final candidates = <String>[
      if (overrideDir != null) overrideDir,
      if (executableDir != null) p.join(executableDir, 'runtime', 'node'),
      p.join(Directory.current.path, 'assets', 'runtime', 'node'),
    ];
    for (final dir in candidates) {
      final paths = RuntimePaths._(
        p.join(dir, 'node.exe'),
        p.join(dir, 'cat_host.js'),
      );
      if (paths.available) return paths;
    }
    // Return the source-tree candidate even when missing, so callers get a
    // deterministic (if non-running) configuration rather than null.
    return RuntimePaths._(
      p.join(candidates.last, 'node.exe'),
      p.join(candidates.last, 'cat_host.js'),
    );
  }
}

/// Resolves the TVBox (Python) runtime: `python.exe` plus our `py_host.py`.
///
/// Two directories are involved because the interpreter is a 39 MB CPython
/// distribution copied in from the original package (git-ignored, synced by
/// `tool/sync_runtime.sh`), while the host script and its `base/` package are
/// ours and live in the repo:
///
///   1. `<executable dir>/runtime/{python,pyhost}/` (packaged build);
///   2. `<project root>/assets/runtime/{python,pyhost}/` (running from source).
class PyRuntimePaths {
  const PyRuntimePaths._(this.python, this.hostScript);

  final String python;
  final String hostScript;

  bool get available =>
      File(python).existsSync() && File(hostScript).existsSync();

  /// [overridePython] is a `<root>/python/python.exe` path (tests point it at
  /// a machine-wide CPython when the bundled one has not been synced yet).
  static PyRuntimePaths resolve({
    String? overridePython,
    String? overrideScript,
    String? executableDir,
  }) {
    final roots = <String>[
      if (executableDir != null) p.join(executableDir, 'runtime'),
      p.join(Directory.current.path, 'assets', 'runtime'),
    ];
    final script =
        overrideScript ?? p.join(roots.last, 'pyhost', 'py_host.py');
    if (overridePython != null) {
      return PyRuntimePaths._(overridePython, script);
    }
    for (final root in roots) {
      final candidate = PyRuntimePaths._(
        p.join(root, 'python', 'python.exe'),
        p.join(root, 'pyhost', 'py_host.py'),
      );
      if (candidate.available) return candidate;
    }
    return PyRuntimePaths._(
      p.join(roots.last, 'python', 'python.exe'),
      script,
    );
  }
}
