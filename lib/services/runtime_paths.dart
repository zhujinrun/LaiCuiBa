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
