import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:parksense/core/format.dart';
import 'package:parksense/core/geo.dart';
import 'package:parksense/domain/clustering.dart';
import 'package:parksense/domain/data_source.dart';
import 'package:parksense/domain/filters.dart';
import 'package:parksense/domain/parking.dart';
import 'package:parksense/domain/tariff_parser.dart';
import 'package:parksense/domain/validation.dart';

Parking pk(
  String id,
  double lat,
  double lng, {
  String source = 'osm',
  ParkingType type = ParkingType.open,
  double? hourly,
  bool? free,
  int? cap,
  int? empty,
  String name = 'Otopark',
}) => Parking(
  id: id,
  sourceId: source,
  name: '$name $id',
  location: GeoPoint(lat, lng),
  type: type,
  price: (hourly != null || free != null) ? PriceInfo(hourly: hourly, isFree: free, sourceId: source) : null,
  occupancy: (cap != null && empty != null) ? Occupancy(capacity: cap, free: empty, observedAt: DateTime.utc(2026)) : null,
);

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('Mesafe hesaplama', () {
    test('Taksim → Kadıköy yaklaşık 6,1 km', () {
      final d = Geo.distanceM(const GeoPoint(41.0369, 28.9850), const GeoPoint(40.9909, 29.0303));
      expect(d, closeTo(6290, 150));
    });
    test('aynı nokta 0 m, simetrik', () {
      const a = GeoPoint(39.92, 32.85), b = GeoPoint(38.42, 27.13);
      expect(Geo.distanceM(a, a), 0);
      expect(Geo.distanceM(a, b), closeTo(Geo.distanceM(b, a), 0.001));
    });
    test('Türkiye ve İstanbul sınırları', () {
      expect(Geo.turkeyBounds.contains(const GeoPoint(41.0, 29.0)), isTrue);
      expect(Geo.turkeyBounds.contains(const GeoPoint(48.85, 2.35)), isFalse);
      expect(Geo.istanbulBounds.intersectsCircle(const GeoPoint(41.03, 28.98), 1000), isTrue);
      expect(Geo.istanbulBounds.intersectsCircle(const GeoPoint(39.92, 32.85), 5000), isFalse);
    });
  });

  group('Biçimlendirme', () {
    test('Türk lirası', () {
      expect(Fmt.tl(45), '₺45');
      expect(Fmt.tl(42.5), '₺42,50');
      expect(Fmt.tl(1250), '₺1.250');
    });
    test('mesafe', () {
      expect(Fmt.distance(434), '430 m');
      expect(Fmt.distance(1540), '1,5 km');
      expect(Fmt.distance(12400), '12 km');
    });
    test('sayı ayrıştırma (TR/EN)', () {
      expect(Fmt.parseNumber('1.250,50'), 1250.5);
      expect(Fmt.parseNumber('1250.5'), 1250.5);
      expect(Fmt.parseNumber('45 TL'), 45);
      expect(Fmt.parseNumber('1.250'), 1250);
      expect(Fmt.parseNumber('abc'), isNull);
    });
    test('Türkçe katlama', () => expect(Fmt.fold('Açık Otopark ığüşöç'), 'ACIK OTOPARK IGUSOC'));
  });

  group('Fiyat hesaplama / tarife ayrıştırma', () {
    test('İSPARK tarife metni', () {
      final p = TariffParser.ispark(tariff: '0-1 Saat : 90 TL;1-2 Saat : 110 TL;0-24 Saat : 250 TL', monthlyFee: 3500, freeMinutes: 15)!;
      expect(p.hourly, 90);
      expect(p.daily, 250);
      expect(p.monthly, 3500);
      expect(p.freeMinutes, 15);
      expect(p.tiers, const [PriceTier('0-1 Saat', 90), PriceTier('1-2 Saat', 110), PriceTier('0-24 Saat', 250)]);
      expect(p.rawText, isNull);
    });
    test('ayrıştırılamayan kısım özgün metin olarak korunur, uydurulmaz', () {
      final p = TariffParser.ispark(tariff: 'Abonelere özel;0-1 Saat: 50,5 TL')!;
      expect(p.hourly, 50.5);
      expect(p.rawText, 'Abonelere özel');
    });
    test('veri yoksa null', () {
      expect(TariffParser.ispark(tariff: '', monthlyFee: 0, freeMinutes: 0), isNull);
      expect(TariffParser.osm(), isNull);
    });
    test('OSM fee/charge', () {
      final a = TariffParser.osm(fee: 'yes', charge: '60 TRY/hour; 300 TRY/day')!;
      expect(a.hourly, 60);
      expect(a.daily, 300);
      expect(a.isFree, isFalse);
      final b = TariffParser.osm(fee: 'no')!;
      expect(b.isFree, isTrue);
      expect(b.effectiveHourly, 0);
      final c = TariffParser.osm(fee: 'yes', charge: 'değişken')!;
      expect(c.hourly, isNull);
      expect(c.rawText, 'değişken');
      expect(TariffParser.osm(charge: '20 TL/saat')!.hourly, 20);
    });
  });

  group('Filtreleme', () {
    const origin = GeoPoint(41.0369, 28.9850);
    final items = [
      pk('a', 41.0372, 28.9861, source: 'ispark', type: ParkingType.indoor, hourly: 90, cap: 400, empty: 150),
      pk('b', 41.0405, 28.9870, source: 'ispark', type: ParkingType.street, hourly: 40, cap: 30, empty: 0),
      pk('c', 41.0330, 28.9790, type: ParkingType.open, hourly: 60),
      pk('d', 41.0470, 28.9900, type: ParkingType.street, free: true),
      pk('e', 41.0600, 29.0200, type: ParkingType.underground),
    ];

    test('filtresiz: tümü mesafeye göre', () {
      final r = ParkingFilter.none.apply(items, origin: origin);
      expect(r.map((p) => p.id), ['a', 'b', 'c', 'd', 'e']);
    });
    test('tür', () {
      expect(const ParkingFilter(types: {ParkingType.street}).apply(items, origin: origin).map((p) => p.id), ['b', 'd']);
    });
    test('mesafe', () {
      expect(const ParkingFilter(maxDistanceM: 1000).apply(items, origin: origin).map((p) => p.id), ['a', 'b', 'c']);
    });
    test('fiyat: bilinmeyenler varsayılan olarak dışarıda, istenirse dahil', () {
      expect(const ParkingFilter(maxHourlyPrice: 60).apply(items, origin: origin).map((p) => p.id), ['b', 'c', 'd']);
      expect(const ParkingFilter(maxHourlyPrice: 60, includeUnknownPrice: true).apply(items, origin: origin).map((p) => p.id), [
        'b',
        'c',
        'd',
        'e',
      ]);
      expect(const ParkingFilter(onlyFree: true).apply(items, origin: origin).map((p) => p.id), ['d']);
    });
    test('doluluk', () {
      expect(const ParkingFilter(occupancy: OccupancyFilter.liveOnly).apply(items).map((p) => p.id).toSet(), {'a', 'b'});
      expect(const ParkingFilter(occupancy: OccupancyFilter.hasSpace).apply(items).map((p) => p.id), ['a']);
      expect(const ParkingFilter(occupancy: OccupancyFilter.lowOccupancy).apply(items).map((p) => p.id), ['a']);
    });
    test('filtreler birlikte çalışır; sonuç yoksa boş liste', () {
      const f = ParkingFilter(types: {ParkingType.street}, maxDistanceM: 1000, maxHourlyPrice: 50);
      expect(f.apply(items, origin: origin).map((p) => p.id), ['b']);
      expect(f.activeCount, 3);
      const none = ParkingFilter(types: {ParkingType.underground}, maxHourlyPrice: 10);
      expect(none.apply(items, origin: origin), isEmpty);
    });
    test('sıralama: fiyat (bilinmeyen sona) ve boş yer', () {
      expect(const ParkingFilter(sort: ParkingSort.price).apply(items, origin: origin).map((p) => p.id), ['d', 'b', 'c', 'a', 'e']);
      expect(const ParkingFilter(sort: ParkingSort.freeSpaces).apply(items, origin: origin).first.id, 'a');
    });
    test('metin araması', () {
      expect(const ParkingFilter(query: 'otopark c').apply(items).map((p) => p.id), ['c']);
    });
    test('OSM kaydının doluluğu "anlık" sayılmaz', () {
      final osmWithOcc = pk('x', 41, 29, source: 'osm', cap: 10, empty: 5);
      expect(osmWithOcc.hasLiveOccupancy, isFalse);
      expect(DataSources.osm.realtimeOccupancy, isFalse);
    });
  });

  group('Doluluk', () {
    test('oran ve sınırlar', () {
      final o = Occupancy(capacity: 400, free: 120, observedAt: DateTime.utc(2026));
      expect(o.occupied, 280);
      expect(o.ratio, closeTo(0.7, 1e-9));
      expect(Occupancy(capacity: 0, free: 0, observedAt: DateTime.utc(2026)).ratio, isNull);
      expect(Occupancy(capacity: 10, free: 0, observedAt: DateTime.utc(2026)).isFull, isTrue);
    });
  });

  group('Kümeleme', () {
    final many = [for (var i = 0; i < 50; i++) pk('$i', 41.03 + i * 0.0001, 28.98 + i * 0.0001)];
    test('uzak yakınlaştırmada az küme, hiçbir otopark kaybolmaz', () {
      final c = Clusterer.cluster(many, 10);
      expect(c.length, lessThan(5));
      expect(c.fold<int>(0, (s, x) => s + x.items.length), 50);
    });
    test('yakın yakınlaştırmada kümeleme kapalı', () {
      expect(Clusterer.cluster(many, 17).length, 50);
    });
  });

  group('Veri doğrulama', () {
    test('ad', () {
      expect(Validators.name(''), isNotNull);
      expect(Validators.name('ab'), isNotNull);
      expect(Validators.name('Merkez Otopark'), isNull);
    });
    test('koordinat', () {
      expect(Validators.latitude('41,0369'), isNull);
      expect(Validators.latitude('95'), isNotNull);
      expect(Validators.longitude('abc'), isNotNull);
      expect(Validators.inTurkey(41.0, 29.0), isNull);
      expect(Validators.inTurkey(48.85, 2.35), isNotNull);
    });
    test('fiyat, kapasite, telefon, web, kaynak', () {
      expect(Validators.optionalPrice(''), isNull);
      expect(Validators.optionalPrice('-5'), isNotNull);
      expect(Validators.optionalPrice('45,50'), isNull);
      expect(Validators.optionalCapacity('12.5'), isNotNull);
      expect(Validators.optionalCapacity('120'), isNull);
      expect(Validators.optionalPhone('+90 212 000 00 00'), isNull);
      expect(Validators.optionalPhone('12ab'), isNotNull);
      expect(Validators.optionalUrl('ornek.com'), isNotNull);
      expect(Validators.optionalUrl('https://ornek.com'), isNull);
      expect(Validators.sourceNote(''), isNotNull);
      expect(Validators.sourceNote('İşletme beyanı'), isNull);
    });
  });
}
