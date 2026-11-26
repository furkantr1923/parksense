import '../../core/failure.dart';
import '../../core/geo.dart';
import '../../core/http.dart';

class PlaceResult {
  const PlaceResult({required this.name, required this.detail, required this.point});

  final String name;
  final String detail;
  final GeoPoint point;
}

/// Adres/şehir arama — OpenStreetMap Nominatim.
///
/// Kullanım politikası gereği: yalnızca kullanıcı aramayı onayladığında
/// istek atılır (otomatik tamamlama yok), saniyede en fazla 1 istek,
/// kimlikli User-Agent, sonuçlar önbelleklenir.
class GeocodingService {
  GeocodingService({this.endpoint = 'https://nominatim.openstreetmap.org/search'});

  String endpoint;
  final _cache = TtlCache<String, List<PlaceResult>>(const Duration(hours: 6), maxEntries: 50);
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// Sık kullanılan şehir merkezleri (konum izni olmadan hızlı başlangıç).
  static const cities = <PlaceResult>[
    PlaceResult(name: 'İstanbul', detail: 'Taksim', point: GeoPoint(41.0369, 28.9850)),
    PlaceResult(name: 'Ankara', detail: 'Kızılay', point: GeoPoint(39.9208, 32.8541)),
    PlaceResult(name: 'İzmir', detail: 'Konak', point: GeoPoint(38.4189, 27.1287)),
    PlaceResult(name: 'Bursa', detail: 'Osmangazi', point: GeoPoint(40.1885, 29.0610)),
    PlaceResult(name: 'Antalya', detail: 'Muratpaşa', point: GeoPoint(36.8869, 30.7043)),
    PlaceResult(name: 'Kadıköy', detail: 'İstanbul', point: GeoPoint(40.9909, 29.0303)),
    PlaceResult(name: 'Konya', detail: 'Selçuklu', point: GeoPoint(37.8746, 32.4932)),
    PlaceResult(name: 'Eskişehir', detail: 'Odunpazarı', point: GeoPoint(39.7767, 30.5206)),
  ];

  Future<List<PlaceResult>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final key = q.toLowerCase();
    final c = _cache.get(key);
    if (c != null) return c;
    final wait = const Duration(milliseconds: 1100) - DateTime.now().difference(_last);
    if (!wait.isNegative) await Future<void>.delayed(wait);
    _last = DateTime.now();
    final uri = Uri.parse(endpoint).replace(
      queryParameters: {'q': q, 'format': 'jsonv2', 'countrycodes': 'tr', 'limit': '8', 'addressdetails': '1', 'accept-language': 'tr'},
    );
    final json = await Http.getJson(uri, source: 'Nominatim');
    final out = parse(json);
    if (out.isEmpty) throw const AppFailure(FailureKind.notFound, source: 'Nominatim');
    _cache.put(key, out);
    return out;
  }

  static List<PlaceResult> parse(dynamic json) {
    if (json is! List) return const [];
    final out = <PlaceResult>[];
    for (final e in json) {
      if (e is! Map) continue;
      final lat = double.tryParse('${e['lat']}');
      final lng = double.tryParse('${e['lon']}');
      if (lat == null || lng == null) continue;
      final display = '${e['display_name'] ?? ''}';
      final parts = display.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty && s != 'Türkiye').toList();
      final name = '${e['name'] ?? ''}'.trim().isNotEmpty ? '${e['name']}'.trim() : (parts.isEmpty ? display : parts.first);
      final detail = parts.where((s) => s != name && !RegExp(r'^\d{5}$').hasMatch(s)).take(3).join(', ');
      out.add(PlaceResult(name: name, detail: detail, point: GeoPoint(lat, lng)));
    }
    return out;
  }
}
