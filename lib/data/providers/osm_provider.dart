import '../../core/failure.dart';
import '../../core/geo.dart';
import '../../core/http.dart';
import '../../domain/data_source.dart';
import '../../domain/parking.dart';
import '../../domain/tariff_parser.dart';
import 'parking_provider.dart';

/// OpenStreetMap verisi — Overpass API üzerinden `amenity=parking`.
///
/// Türkiye genelinde çalışır ancak kapsam gönüllü katkısına bağlıdır;
/// anlık doluluk içermez. Kullanım politikasına uygun olarak: kimlikli
/// User-Agent, sınırlı sonuç sayısı, önbellek ve yedek sunucu.
class OsmProvider implements ParkingProvider {
  OsmProvider({List<String>? endpoints})
    : endpoints = endpoints ?? const ['https://overpass-api.de/api/interpreter', 'https://overpass.private.coffee/api/interpreter'];

  List<String> endpoints;

  /// Aynı bölge 30 dakika içinde tekrar sorgulanmaz.
  final _cache = TtlCache<String, ProviderResult>(const Duration(minutes: 30), maxEntries: 24);

  static const maxResults = 600;

  @override
  DataSourceInfo get info => DataSources.osm;

  @override
  bool covers(SearchArea area) => Geo.turkeyBounds.intersectsCircle(area.center, area.radiusM);

  static String buildQuery(SearchArea a) {
    final lat = a.center.lat.toStringAsFixed(5);
    final lng = a.center.lng.toStringAsFixed(5);
    final r = a.radiusM.round();
    // Özel (access=private/no) otoparklar ve kişisel garajlar hariç tutulur.
    return '[out:json][timeout:25];'
        'nwr["amenity"="parking"]["access"!~"^(private|no)\$"]["parking"!~"^(garage_boxes|carports)\$"](around:$r,$lat,$lng);'
        'out center tags $maxResults;';
  }

  @override
  Future<ProviderResult> fetch(SearchArea area) async {
    final cached = _cache.get(area.key);
    if (cached != null) return cached;
    Object? lastError;
    for (final ep in endpoints) {
      try {
        final json = await Http.postFormJson(Uri.parse(ep), {'data': buildQuery(area)}, source: info.name);
        final result = parse(json, DateTime.now().toUtc());
        _cache.put(area.key, result);
        return result;
      } catch (e) {
        lastError = e; // Yedek sunucuyu dene.
      }
    }
    throw AppFailure.from(lastError ?? const AppFailure(FailureKind.unknown), source: info.name);
  }

  void clearCache() => _cache.clear();

  static ParkingType parseType(Map tags) {
    final p = tags['parking']?.toString();
    switch (p) {
      case 'surface':
        return ParkingType.open;
      case 'multi-storey':
      case 'rooftop':
        return ParkingType.multiStorey;
      case 'underground':
        return ParkingType.underground;
      case 'street_side':
      case 'lane':
      case 'on_street':
      case 'layby':
        return ParkingType.street;
      case 'garage':
        return ParkingType.indoor;
    }
    if (tags['covered'] == 'yes' || tags['indoor'] == 'yes') return ParkingType.indoor;
    return ParkingType.unknown;
  }

  static ProviderResult parse(dynamic json, DateTime fetchedAt) {
    if (json is! Map || json['elements'] is! List) throw const FormatException('Overpass: elements yok');
    DateTime? dataTime;
    final osm3s = json['osm3s'];
    if (osm3s is Map) dataTime = DateTime.tryParse('${osm3s['timestamp_osm_base']}')?.toUtc();
    final out = <Parking>[];
    for (final e in json['elements'] as List) {
      if (e is! Map) continue;
      final tags = e['tags'] is Map ? e['tags'] as Map : const {};
      final type = e['type']?.toString() ?? 'node';
      final id = e['id'];
      double? lat = (e['lat'] as num?)?.toDouble();
      double? lng = (e['lon'] as num?)?.toDouble();
      final center = e['center'];
      if ((lat == null || lng == null) && center is Map) {
        lat = (center['lat'] as num?)?.toDouble();
        lng = (center['lon'] as num?)?.toDouble();
      }
      if (id == null || lat == null || lng == null) continue;
      final point = GeoPoint(lat, lng);
      if (!point.isValid) continue;
      String? t(String k) {
        final v = tags[k]?.toString().trim();
        return (v == null || v.isEmpty) ? null : v;
      }

      final name = t('name:tr') ?? t('name') ?? t('operator');
      final street = [t('addr:street'), t('addr:housenumber')].whereType<String>().join(' ');
      final hood = t('addr:neighbourhood') ?? t('addr:suburb');
      final address = [?hood, if (street.isNotEmpty) street].join(', ');
      final opening = t('opening_hours');
      final wheelchair = t('wheelchair');
      final disabledCap = int.tryParse(t('capacity:disabled') ?? '');
      final accessibility = <String>[
        if (wheelchair == 'yes') 'Tekerlekli sandalye ile erişilebilir',
        if (wheelchair == 'limited') 'Kısmen erişilebilir',
        if (wheelchair == 'no') 'Tekerlekli sandalye erişimi yok',
        if (disabledCap != null && disabledCap > 0) '$disabledCap engelli park yeri',
        if (t('capacity:disabled') == 'yes') 'Engelli park yeri var',
      ];
      final charging = t('capacity:charging');
      final amenities = <String>[
        if (charging != null && charging != 'no' && charging != '0') 'Elektrikli araç şarjı',
        if (t('supervised') == 'yes') 'Güvenlikli',
        if (t('covered') == 'yes') 'Üstü kapalı',
        if (t('lit') == 'yes') 'Aydınlatmalı',
        if (t('surface') == 'asphalt' || t('surface') == 'paved') 'Asfalt zemin',
        if (t('maxstay') != null) 'Azami süre: ${t('maxstay')}',
        if (t('maxheight') != null) 'Azami yükseklik: ${t('maxheight')}',
      ];
      final access = t('access');
      final image = t('image');
      out.add(
        Parking(
          id: 'osm:$type/$id',
          sourceId: DataSources.osm.id,
          name: name ?? 'Adı belirtilmemiş otopark',
          nameIsGenerated: name == null,
          location: point,
          address: address.isEmpty ? null : address,
          district: t('addr:district'),
          city: t('addr:city') ?? t('addr:province'),
          type: parseType(tags),
          isOpenNow: opening == '24/7' ? true : null,
          openingHours: opening == '24/7' ? '7/24 açık' : opening,
          capacity: int.tryParse(t('capacity') ?? ''),
          price: TariffParser.osm(fee: t('fee'), charge: t('charge'), updatedAt: dataTime),
          phone: t('phone') ?? t('contact:phone'),
          website: t('website') ?? t('contact:website'),
          photos: [if (image != null && image.startsWith('https://')) image],
          accessibility: accessibility.isEmpty ? null : accessibility.join(' · '),
          amenities: amenities,
          operatorName: t('operator'),
          accessNote: switch (access) {
            'customers' => 'Yalnızca müşterilere açık',
            'permissive' => 'Sahibinin izniyle kamuya açık',
            'destination' => 'Yalnızca varış noktası için',
            _ => null,
          },
          sourceRef: 'https://www.openstreetmap.org/$type/$id',
          updatedAt: dataTime,
          fetchedAt: fetchedAt,
        ),
      );
    }
    return ProviderResult(out, dataTime: dataTime);
  }
}
