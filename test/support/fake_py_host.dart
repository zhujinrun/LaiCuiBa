import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/py_host.dart';
import 'package:lai_cui_ba/services/py_runtime.dart';
import 'package:lai_cui_ba/services/tvbox_source.dart';

/// A [PyHost] that answers from a table instead of an interpreter.
///
/// The store and the proxy server do not care how a body was produced -- only
/// that `py_host` answered one line of JSON per call. Standing in at this seam
/// lets those two be tested without a 39 MB runtime on the test machine, while
/// the real protocol gets its own test (`py_host_e2e_test.dart`) against a real
/// `python.exe`.
class FakePyHost extends PyHost {
  FakePyHost({required this.bodies, this.proxyAnswer})
    : super(pythonPath: 'python.exe', hostScript: 'py_host.py');

  /// `method` → the body that method returns. A method with no entry raises,
  /// which is exactly what a source missing `homeContent` does.
  final Map<String, String Function(List<Object?> args)> bodies;

  /// What `/proxy` answers. Null makes the fake behave like a source that does
  /// not implement `localProxy`.
  final PyProxyResponse? proxyAnswer;

  /// Methods asked for, in order — lets a test prove a call was made once.
  final List<String> calls = [];

  /// The last `[flag, id, vipFlags]` a `player` call carried.
  List<Object?>? lastPlayerArgs;

  /// The last `ext` a call carried (what `init()` received).
  String? lastExt;

  @override
  Future<String> call({
    required String key,
    required String path,
    required String method,
    String ext = '',
    List<Object?> args = const [],
  }) async {
    calls.add(method);
    lastExt = ext;
    if (method == 'player') lastPlayerArgs = args;
    final body = bodies[method];
    if (body == null) {
      throw PyHostException('源没有实现 $method');
    }
    return body(args);
  }

  @override
  Future<PyProxyResponse> proxy(
    Map<String, dynamic> params, {
    Duration? timeout,
  }) async {
    final answer = proxyAnswer;
    if (answer == null) throw const PyHostException('没有可用的源实例');
    return answer;
  }
}

/// The [PySources] seam: hands back a [TvBoxSource] over [host] for every site,
/// as if the interpreter were up and the file already on disk.
class FakePySources implements PySources {
  FakePySources(this.host);

  final PyHost host;

  /// Sites asked for, in order.
  final List<SiteInfo> asked = [];

  /// What [expandSites] answers. Null means "nothing expanded", the default.
  List<SiteInfo>? expansion;

  @override
  String? lastError;

  @override
  Future<List<SiteInfo>?> expandSites(SourceInfo source) async => expansion;

  @override
  Future<TvBoxSource?> sourceFor({
    required SourceInfo source,
    required SiteInfo site,
  }) async {
    asked.add(site);
    return TvBoxSource(
      host: host,
      key: '${source.id}|${site.key}',
      path: site.api,
      ext: site.ext,
      siteKey: site.key,
    );
  }

  @override
  Future<void> dispose() async {}
}
