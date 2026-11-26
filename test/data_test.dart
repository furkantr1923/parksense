import 'package:flutter_test/flutter_test.dart';
import 'package:parksense/core/failure.dart';
import 'package:parksense/core/geo.dart';
import 'package:parksense/data/db/app_database.dart';
import 'package:parksense/data/parking_repository.dart';
import 'package:parksense/data/providers/geocoding.dart';
import 'package:parksense/data/providers/ispark_provider.dart';
import 'package:parksense/data/providers/osm_provider.dart';
import 'package:parksense/data/providers/parking_provider.dart';
import 'package:parksense/domain/data_source.dart';
import 'package:parksense/domain/parking.dart';
import 'package:parksense/services/navigation_service.dart';
import 'package:parksense/services/update_service.dart';

import 'fixtures.dart';

/// Ağa çıkmayan sahte sağlayıcılar (entegrasyon testleri için).
class FakeIspark extends IsparkProvider {
  FakeIspark({this.fail = false});
  bool fail;
  int calls = 0;

  @override
  Future<List<Parking>> fetchAll({bool force = false}) async {
    calls++;
    if (fail) throw const AppFailure(FailureKind.offline, source: 'İSPARK');
    return IsparkProvider.parseList(isparkListJson, DateTime.utc(2026, 11, 26, 11));
  }

  @override
  Future<Parking> enrich(Parking base, {bool force = false}) async =>
      IsparkProvider.parseDetail(Map<String, dynamic>.from(isparkDetailJson), base, DateTime.utc(2026, 11, 26, 11, 5));
}

class FakeOsm extends OsmProvider {
  FakeOsm({this.fail = false});
  bool fail;

  @override
  Future<ProviderResult> fetch(SearchArea area) async {
    if (fail) throw const AppFailure(FailureKind.timeout, source: 'OSM');
    return OsmProvider.parse(overpassJson, DateTime.utc(2026, 11, 26, 11));
  }
}

const taksim = GeoPoint(41.0369, 28.9850);

void main() {
  group('İSPARK sağlayıcısı', () {
    final list = IsparkProvider.parseList(isparkListJson, DateTime.utc(2026, 11, 26, 11));

    test('geçerli kayıtlar ayrıştırılır, geçersizler ayıklanır', () {
      expect(list.map((p) => p.id), ['ispark:1001', 'ispark:1002', 'ispark:1003']);
    });
    test('alanlar doğru eşlenir', () {
      final a = list.first;
      expect(a.name, 'Taksim Katlı Otoparkı');
      expect(a.district, 'Beyoğlu');
      expect(a.type, ParkingType.indoor);
      expect(a.isOpenNow, isTrue);
      expect(a.occupancy!.capacity, 400);
      expect(a.occupancy!.free, 120);
      expect(a.hasLiveOccupancy, isTrue);
      expect(a.price!.freeMinutes, 15);
      expect(list[1].type, ParkingType.street);
      expect(list[1].occupancy!.isFull, isTrue);
    });
    test('kapasitesi 0 olan kayıtta doluluk uydurulmaz', () {
      expect(list[2].occupancy, isNull);
      expect(list[2].isOpenNow, isFalse);
    });
    test('eski Türkçe alan adları desteklenir', () {
      final l = IsparkProvider.parseList(isparkLegacyJson, DateTime.utc(2026));
      expect(l.single.name, 'Eski Biçim Otoparkı');
      expect(l.single.occupancy!.free, 10);
    });
    test('detay: tarife, abonelik, adres ve kaynağın güncelleme zamanı', () {
      final d = IsparkProvider.parseDetail(Map<String, dynamic>.from(isparkDetailJson), list.first, DateTime.utc(2026, 11, 26, 11, 30));
      expect(d.price!.hourly, 90);
      expect(d.price!.daily, 250);
      expect(d.price!.monthly, 3500);
      expect(d.address, 'Gümüşsuyu Mah. İnönü Cad.');
      expect(d.occupancy!.free, 118);
      expect(d.occupancy!.observedAt, DateTime.utc(2026, 11, 26, 11, 5)); // 14:05 TSİ = 11:05 UTC
      expect(d.occupancy!.observedAtIsFetchTime, isFalse);
    });
    test('liste yerine nesne gelirse anlaşılır hata', () {
      expect(() => IsparkProvider.parseList({'x': 1}, DateTime.utc(2026)), throwsFormatException);
    });
    test('yalnızca İstanbul\'u kapsar', () {
      final p = IsparkProvider();
      expect(p.covers(const SearchArea(taksim, 3000)), isTrue);
      expect(p.covers(const SearchArea(GeoPoint(39.92, 32.85), 3000)), isFalse);
    });
  });

  group('OpenStreetMap sağlayıcısı', () {
    final r = OsmProvider.parse(overpassJson, DateTime.utc(2026, 11, 26, 11));

    test('ayrıştırma ve OSM veri zamanı', () {
      expect(r.items.length, 3);
      expect(r.dataTime, DateTime.utc(2026, 11, 26, 10));
    });
    test('etiketler', () {
      final b = r.items.firstWhere((p) => p.id == 'osm:node/502');
      expect(b.type, ParkingType.open);
      expect(b.capacity, 80);
      expect(b.price!.hourly, 60);
      expect(b.price!.daily, 300);
      expect(b.openingHours, '7/24 açık');
      expect(b.isOpenNow, isTrue);
      expect(b.accessibility, contains('Tekerlekli'));
      expect(b.amenities, contains('Elektrikli araç şarjı'));
      expect(b.address, 'Tarlabaşı Bulvarı 10');
      expect(b.occupancy, isNull);
      expect(b.sourceRef, 'https://www.openstreetmap.org/node/502');
    });
    test('adı olmayan kayıt işaretlenir', () {
      final c = r.items.firstWhere((p) => p.id == 'osm:node/503');
      expect(c.nameIsGenerated, isTrue);
      expect(c.price!.isFree, isTrue);
      expect(c.type, ParkingType.street);
    });
    test('Overpass sorgusu: özel otoparklar hariç, sonuç sınırlı', () {
      final q = OsmProvider.buildQuery(const SearchArea(taksim, 2500));
      expect(q, contains('around:2500,41.03690,28.98500'));
      expect(q, contains('"access"!~"^(private|no)\$"'));
      expect(q, contains('out center tags ${OsmProvider.maxResults}'));
    });
  });

  group('Nominatim', () {
    test('ayrıştırma', () {
      final r = GeocodingService.parse(nominatimJson);
      expect(r.length, 1);
      expect(r.first.name, 'Kadıköy');
      expect(r.first.detail, 'İstanbul, Marmara Bölgesi');
    });
  });

  group('Depo (entegrasyon: sağlayıcılar + SQLite)', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.inMemory());
    tearDown(() => db.close());

    test('kaynaklar birleştirilir, İSPARK ile çakışan OSM kaydı ayıklanır', () async {
      final repo = ParkingRepository(db: db, ispark: FakeIspark(), osm: FakeOsm());
      final out = await repo.search(const SearchArea(taksim, 3000));
      expect(out.items.any((p) => p.id == 'osm:way/501'), isFalse, reason: 'İSPARK 1001 ile aynı yer');
      expect(out.counts['ispark'], 3);
      expect(out.counts['osm'], 2);
      expect(out.fromCache, isFalse);
      expect(db.parkingCount, 5, reason: 'önbelleğe yazıldı');
    });

    test('bir kaynak başarısızsa diğerleri gösterilir ve uyarı verilir', () async {
      final repo = ParkingRepository(db: db, ispark: FakeIspark(fail: true), osm: FakeOsm());
      final out = await repo.search(const SearchArea(taksim, 3000));
      expect(out.items.length, 3);
      expect(out.warnings.single, contains('İSPARK'));
      expect(out.fromCache, isFalse);
    });

    test('internet yokken önbellek gösterilir ve doluluk GÖSTERİLMEZ', () async {
      await ParkingRepository(db: db, ispark: FakeIspark(), osm: FakeOsm()).search(const SearchArea(taksim, 3000));
      final offline = ParkingRepository(db: db, ispark: FakeIspark(fail: true), osm: FakeOsm(fail: true));
      final out = await offline.search(const SearchArea(taksim, 3000));
      expect(out.fromCache, isTrue);
      expect(out.items.length, 5);
      expect(out.items.every((p) => p.occupancy == null), isTrue);
      expect(out.warnings.length, 2);
    });

    test('İstanbul dışında İSPARK sorgulanmaz', () async {
      final ispark = FakeIspark();
      final repo = ParkingRepository(db: db, ispark: ispark, osm: FakeOsm());
      await repo.search(const SearchArea(GeoPoint(39.92, 32.85), 3000));
      expect(ispark.calls, 0);
    });

    test('detay zenginleştirme kalıcı olur, sonraki liste güncellemesi tarifeyi silmez', () async {
      final repo = ParkingRepository(db: db, ispark: FakeIspark(), osm: FakeOsm());
      final out = await repo.search(const SearchArea(taksim, 3000));
      final rich = await repo.details(out.items.firstWhere((p) => p.id == 'ispark:1001'));
      expect(rich.price!.monthly, 3500);
      await repo.search(const SearchArea(taksim, 3000)); // liste yeniden yazılır
      final stored = db.parking('ispark:1001')!;
      expect(stored.price!.monthly, 3500);
      expect(stored.price!.tiers.length, 4);
      expect(stored.address, 'Gümüşsuyu Mah. İnönü Cad.');
    });
  });

  group('Navigasyon bağlantıları', () {
    test('Google Maps evrensel URL ve uygulama şeması', () {
      expect(
        NavigationService.webUri(taksim).toString(),
        'https://www.google.com/maps/dir/?api=1&destination=41.036900%2C28.985000&travelmode=driving',
      );
      expect(NavigationService.appUri(taksim).toString(), 'google.navigation:q=41.036900,28.985000&mode=d');
    });
    test('telefon ve web sitesi', () {
      expect(NavigationService.phoneUri('+90 (212) 000 00 00').toString(), 'tel:+902120000000');
      expect(NavigationService.phoneUri('12'), isNull);
      expect(NavigationService.websiteUri('ornek.com').toString(), 'https://ornek.com');
    });
  });

  group('Güncelleme denetimi', () {
    test('sürüm karşılaştırma', () {
      expect(UpdateService.compareVersions('v1.1.0', '1.0.0'), greaterThan(0));
      expect(UpdateService.compareVersions('1.0.0', '1.0.0'), 0);
      expect(UpdateService.compareVersions('1.0.9', '1.1'), lessThan(0));
    });
    test('uç nokta yoksa "yapılandırılmamış" der, çalışıyormuş gibi davranmaz', () async {
      final r = await const UpdateService().check('');
      expect(r.state, UpdateState.notConfigured);
    });
  });

  test('veri kaynakları kataloğu', () {
    expect(DataSources.all.map((s) => s.id), ['ispark', 'osm', 'local']);
    expect(DataSources.ispark.realtimeOccupancy, isTrue);
    expect(DataSources.byId('bilinmeyen').id, 'local');
  });
}
