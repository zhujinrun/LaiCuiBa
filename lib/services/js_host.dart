import 'source_host.dart';

/// The Node side of [SourceHost]: `node.exe` running `js_site_host.js`.
///
/// This is a *different* runtime from the 猫源 host (`cat_host.js`). A catvod
/// bundle answers `start(config)`; a TVBox `.js` site is a file of synchronous
/// global functions (`homeContent`, `pdfh`, `req`, …). The bridge implements
/// those globals in Node, and speaks the same line-JSON protocol as
/// `py_host.py`, so one client drives both.
class JsHost extends SourceHost {
  JsHost({
    required String nodePath,
    required String hostScript,
    required String dataDir,
    super.callTimeout,
  }) : super(
         executable: nodePath,
         script: hostScript,
         label: 'js',
         // The source's `local` store lands here instead of next to the runtime,
         // which may be a read-only install directory.
         environment: {'LCB_JS_DATA': dataDir},
       );
}
