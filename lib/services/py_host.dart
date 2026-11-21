import 'source_host.dart';

/// The CPython side of [SourceHost]: the embedded interpreter running
/// `py_host.py`.
///
/// Everything the protocol needs lives in the base class; this only names the
/// binary and the script, so a Python source and a `.js` source are driven by
/// exactly the same client code.
class PyHost extends SourceHost {
  PyHost({
    required String pythonPath,
    required String hostScript,
    super.callTimeout,
  }) : super(
         executable: pythonPath,
         script: hostScript,
         label: 'Python',
       );
}

/// Names kept for callers that predate the shared bus; both now live in
/// `source_host.dart`.
typedef PyHostException = SourceHostException;
typedef PyProxyResponse = SourceProxyResponse;
typedef PySubSite = SourceSubSite;
