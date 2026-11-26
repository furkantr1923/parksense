import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/http.dart';
import '../../domain/data_source.dart';
import '../../domain/parking.dart';
import '../../domain/tariff_parser.dart';
import 'parking_provider.dart';

/// İstanbul Büyükşehir Belediyesi Açık Veri Portalı — İSPARK servisi.
///
/// - `GET /ispark/Park` → tüm otoparklar, kapasite ve **anlık boş yer**.
/// - `GET /ispark/ParkDetay?id=…` → adres, tarife, abonelik, güncelleme zamanı.
///
/// Anahtar gerektirmez. Doluluk bilgisi gerçek zamanlıdır ve resmî kaynaktır.
class IsparkProvider implements ParkingProvider {
  IsparkProvider({this.baseUrl = 'https://api.ibb.gov.tr/ispark'});

  String baseUrl;

  /// Liste ~1 MB'tan küçüktür; 2 dakika önbelleklenir (doluluk tazeliği ile
  /// istek sayısı arasında denge).
  final _listCache = TtlCache<String, List<Parking>>(const Duration(minutes: 2), maxEntries: 1);
  final _detailCache = TtlCache<String, Parking>(const Duration(minutes: 2), maxEntries: 64);

  @override
  DataSourceInfo get info => DataSources.ispark;

  @override
  bool covers(SearchArea area) => Geo.istanbulBounds.intersectsCircle(area.center, area.radiusM);

  @override
  Future<ProviderResult> fetch(SearchArea area) async {
    final all = await fetchAll();
    final inside = all.where((p) => Geo.distanceM(area.center, p.location) <= area.radiusM).toList();
    return ProviderResult(inside, dataTime: all.isEmpty ? null : all.first.fetchedAt);
  }

  Future<List<Parking>> fetchAll({bool force = false}) async {
    if (!force) {
      final c = _listCache.get('all');
      if (c != null) return c;
    }
    final json = await Http.getJson(Uri.parse('$baseUrl/Park'), source: info.name);
    final list = parseList(json, DateTime.now().toUtc());
    _listCache.put('all', list);
    return list;
  }

  /// Detay: adres, tarife ve kaynağın kendi güncelleme zamanı ile zenginleştirir.
  Future<Parking> enrich(Parking base, {bool force = false}) async {
    final raw = base.id.substring('ispark:'.length);
    if (!force) {
      final c = _detailCache.get(raw);
      if (c != null) return c;
    }
    final json = await Http.getJson(Uri.parse('$baseUrl/ParkDetay?id=$raw'), source: info.name);
    final obj = json is List ? (json.isEmpty ? null : json.first) : json;
    if (obj is! Map) return base;
    final p = parseDetail(Map<String, dynamic>.from(obj), base, DateTime.now().toUtc());
    _detailCache.put(raw, p);
    return p;
  }

  void clearCache() {
    _listCache.clear();
    _detailCache.clear();
  }

  // ---------------------------------------------------------------- ayrıştırma

  static Object? _pick(Map m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null) return m[k];
    }
    return null;
  }

  static double? _num(Object? v) => v is num ? v.toDouble() : Fmt.parseNumber(v?.toString());

  static int? _int(Object? v) => _num(v)?.round();

  static String? _str(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty || s.toLowerCase() == 'null') ? null : s;
  }

  static ParkingType parseType(String? raw) {
    if (raw == null) return ParkingType.unknown;
    final t = Fmt.fold(raw);
    if (t.contains('YOL')) return ParkingType.street;
    if (t.contains('KATLI')) return ParkingType.multiStorey;
    if (t.contains('YER ALTI') || t.contains('YERALTI')) return ParkingType.underground;
    if (t.contains('KAPALI')) return ParkingType.indoor;
    if (t.contains('ACIK')) return ParkingType.open;
    return ParkingType.unknown;
  }

  static String _titleCase(String s) {
    // İSPARK adları büyük harfle gelir: "TAKSİM KATLI OTOPARKI" → "Taksim Katlı Otoparkı".
    if (s != s.toUpperCase()) return s;
    return s
        .split(RegExp(r'\s+'))
        .map((w) {
          if (w.isEmpty) return w;
          final lower = w.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
          final first = lower[0] == 'i' ? 'İ' : (lower[0] == 'ı' ? 'I' : lower[0].toUpperCase());
          return first + lower.substring(1);
        })
        .join(' ');
  }

  static List<Parking> parseList(dynamic json, DateTime fetchedAt) {
    if (json is! List) throw const FormatException('İSPARK: liste bekleniyordu');
    final out = <Parking>[];
    for (final e in json) {
      if (e is! Map) continue;
      final id = _int(_pick(e, ['parkID', 'ParkID', 'parkId', 'id']));
      final lat = _num(_pick(e, ['lat', 'Lat', 'latitude', 'Latitude']));
      final lng = _num(_pick(e, ['lng', 'Lng', 'lon', 'longitude', 'Longitude']));
      final name = _str(_pick(e, ['parkName', 'ParkAdi', 'name']));
      if (id == null || lat == null || lng == null || name == null) continue;
      final point = GeoPoint(lat, lng);
      if (!point.isValid || !Geo.turkeyBounds.contains(point)) continue;
      final capacity = _int(_pick(e, ['capacity', 'Kapasitesi', 'Capacity']));
      final free = _int(_pick(e, ['emptyCapacity', 'BosKapasite', 'EmptyCapacity']));
      final isOpenRaw = _pick(e, ['isOpen', 'IsOpen']);
      final freeTime = _int(_pick(e, ['freeTime', 'UcretsizParklanmaDk', 'FreeTime']));
      Occupancy? occ;
      if (capacity != null && capacity > 0 && free != null && free >= 0) {
        occ = Occupancy(capacity: capacity, free: free.clamp(0, capacity), observedAt: fetchedAt, observedAtIsFetchTime: true);
      }
      out.add(
        Parking(
          id: 'ispark:$id',
          sourceId: DataSources.ispark.id,
          name: _titleCase(name),
          location: point,
          district: _str(_pick(e, ['district', 'Ilce', 'District'])) == null
              ? null
              : _titleCase(_str(_pick(e, ['district', 'Ilce', 'District']))!),
          city: 'İstanbul',
          type: parseType(_str(_pick(e, ['parkType', 'ParkTipi', 'ParkType']))),
          isOpenNow: isOpenRaw == null
              ? null
              : (isOpenRaw == true || isOpenRaw == 1 || isOpenRaw.toString() == '1' || isOpenRaw.toString().toLowerCase() == 'true'),
          openingHours: _str(_pick(e, ['workHours', 'CalismaSaatleri', 'WorkHours'])),
          capacity: capacity,
          occupancy: occ,
          price: (freeTime != null && freeTime > 0) ? PriceInfo(freeMinutes: freeTime, sourceId: 'ispark', updatedAt: fetchedAt) : null,
          operatorName: 'İSPARK A.Ş.',
          fetchedAt: fetchedAt,
          updatedAt: fetchedAt,
        ),
      );
    }
    return out;
  }

  /// "26.11.2026 14:05:00", "2026-11-26T14:05:00" vb. İstanbul yerel saati (UTC+3) kabul edilir.
  static DateTime? parseIstanbulTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final s = raw.trim();
    final iso = DateTime.tryParse(s);
    if (iso != null) {
      return iso.isUtc
          ? iso
          : DateTime.utc(iso.year, iso.month, iso.day, iso.hour, iso.minute, iso.second).subtract(const Duration(hours: 3));
    }
    final m = RegExp(r'^(\d{1,2})[./](\d{1,2})[./](\d{4})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?').firstMatch(s);
    if (m == null) return null;
    final dt = DateTime.utc(
      int.parse(m.group(3)!),
      int.parse(m.group(2)!),
      int.parse(m.group(1)!),
      int.tryParse(m.group(4) ?? '') ?? 0,
      int.tryParse(m.group(5) ?? '') ?? 0,
      int.tryParse(m.group(6) ?? '') ?? 0,
    );
    return dt.subtract(const Duration(hours: 3));
  }

  static Parking parseDetail(Map<String, dynamic> e, Parking base, DateTime fetchedAt) {
    final updated = parseIstanbulTime(_str(_pick(e, ['updateDate', 'GuncellemeTarihi', 'UpdateDate'])));
    final capacity = _int(_pick(e, ['capacity', 'Kapasitesi'])) ?? base.capacity;
    final free = _int(_pick(e, ['emptyCapacity', 'BosKapasite']));
    Occupancy? occ = base.occupancy;
    if (capacity != null && capacity > 0 && free != null && free >= 0) {
      occ = Occupancy(
        capacity: capacity,
        free: free.clamp(0, capacity),
        observedAt: updated ?? fetchedAt,
        observedAtIsFetchTime: updated == null,
      );
    }
    final price = TariffParser.ispark(
      tariff: _str(_pick(e, ['tariff', 'Tarife', 'Tariff'])),
      monthlyFee: _num(_pick(e, ['monthlyFee', 'AylikAbonelikUcreti', 'MonthlyFee'])),
      freeMinutes: _int(_pick(e, ['freeTime', 'UcretsizParklanmaDk'])) ?? base.price?.freeMinutes,
      updatedAt: updated ?? fetchedAt,
    );
    final address = _str(_pick(e, ['address', 'Adres', 'Address']));
    return base.copyWith(
      occupancy: occ,
      price: price ?? base.price,
      address: address,
      updatedAt: updated ?? fetchedAt,
      fetchedAt: fetchedAt,
    );
  }
}
