import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app/app_info.dart';
import 'failure.dart';

/// Tüm ağ isteklerinin geçtiği ince katman: kimlikli User-Agent,
/// zaman aşımı ve türlendirilmiş hatalar.
class Http {
  Http._();

  static http.Client client = http.Client();

  static Map<String, String> get headers => {'User-Agent': AppInfo.userAgent, 'Accept': 'application/json', 'Accept-Language': 'tr'};

  static Future<dynamic> getJson(Uri uri, {required String source, Duration timeout = const Duration(seconds: 20)}) async {
    final res = await _guard(() => client.get(uri, headers: headers), source, timeout);
    return _decode(res, source);
  }

  static Future<dynamic> postFormJson(
    Uri uri,
    Map<String, String> body, {
    required String source,
    Duration timeout = const Duration(seconds: 35),
  }) async {
    final res = await _guard(() => client.post(uri, headers: headers, body: body), source, timeout);
    return _decode(res, source);
  }

  /// Yalnızca HTTP durum kodunu döndürür (öz-sınama: harita döşemeleri vb.).
  static Future<int> status(String url, {Duration timeout = const Duration(seconds: 20)}) async {
    final res = await _guard(() => client.get(Uri.parse(url), headers: {'User-Agent': AppInfo.userAgent}), url, timeout);
    return res.statusCode;
  }

  static Future<http.Response> _guard(Future<http.Response> Function() f, String source, Duration timeout) async {
    try {
      return await f().timeout(timeout);
    } catch (e) {
      throw AppFailure.from(e, source: source);
    }
  }

  static dynamic _decode(http.Response res, String source) {
    if (res.statusCode == 404) throw AppFailure(FailureKind.notFound, source: source, detail: 'HTTP 404');
    if (res.statusCode == 429 || res.statusCode >= 500) {
      throw AppFailure(FailureKind.server, source: source, detail: 'HTTP ${res.statusCode}');
    }
    if (res.statusCode != 200) {
      throw AppFailure(FailureKind.invalidResponse, source: source, detail: 'HTTP ${res.statusCode}');
    }
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException catch (e) {
      throw AppFailure(FailureKind.invalidResponse, source: source, detail: e.message);
    }
  }
}

/// Basit süre sınırlı bellek önbelleği (gereksiz API isteklerini önler).
class TtlCache<K, V> {
  TtlCache(this.ttl, {this.maxEntries = 32});

  final Duration ttl;
  final int maxEntries;
  final _map = <K, (DateTime, V)>{};

  V? get(K key) {
    final e = _map[key];
    if (e == null) return null;
    if (DateTime.now().difference(e.$1) > ttl) {
      _map.remove(key);
      return null;
    }
    return e.$2;
  }

  void put(K key, V value) {
    if (_map.length >= maxEntries) _map.remove(_map.keys.first);
    _map[key] = (DateTime.now(), value);
  }

  void clear() => _map.clear();
}
