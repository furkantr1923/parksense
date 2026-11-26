import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parksense/core/geo.dart';
import 'package:parksense/data/db/app_database.dart';
import 'package:parksense/domain/data_source.dart';
import 'package:parksense/domain/parking.dart';

Parking remote(String id, {double lat = 41.03, double lng = 28.98, PriceInfo? price, DateTime? fetched}) => Parking(
  id: 'osm:node/$id',
  sourceId: 'osm',
  name: 'Uzak $id',
  location: GeoPoint(lat, lng),
  price: price,
  fetchedAt: fetched ?? DateTime.now().toUtc(),
  amenities: const ['Güvenlikli'],
);

Parking local(String id, {int? capacity, double? hourly}) => Parking(
  id: 'local:$id',
  sourceId: DataSources.local.id,
  name: 'Yerel $id',
  location: const GeoPoint(41.04, 28.99),
  type: ParkingType.multiStorey,
  capacity: capacity,
  price: hourly == null ? null : PriceInfo(hourly: hourly, sourceId: 'local'),
);

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.inMemory());
  tearDown(() => db.close());

  test('şema: 8 tablo, sürüm, yabancı anahtarlar açık, veri kaynakları yüklü', () {
    expect(db.userVersion, AppDatabase.schemaVersion);
    expect(db.foreignKeysOn, isTrue);
    expect(db.dataSourceRows().map((r) => r['id']), ['ispark', 'local', 'osm']);
  });

  test('ekle / oku: tüm alanlar ve fiyatlar gidiş-dönüş', () {
    db.upsertParkings([
      remote(
        '1',
        price: const PriceInfo(hourly: 40, daily: 200, isFree: false, rawText: 'not', sourceId: 'osm'),
      ),
    ]);
    final p = db.parking('osm:node/1')!;
    expect(p.name, 'Uzak 1');
    expect(p.amenities, ['Güvenlikli']);
    expect(p.price!.hourly, 40);
    expect(p.price!.daily, 200);
    expect(p.price!.isFree, isFalse);
    expect(p.price!.rawText, 'not');
    expect(p.occupancy, isNull, reason: 'veritabanından okunan kayıtta doluluk olmaz');
  });

  group('Favori işlemleri', () {
    test('ekle, listele, kaldır', () {
      final p = remote('1');
      db.setFavorite(p, true);
      db.setFavorite(p, true); // iki kez eklemek çoğaltmaz
      expect(db.favoriteIds(), {'osm:node/1'});
      expect(db.favorites().single.name, 'Uzak 1');
      db.setFavorite(p, false);
      expect(db.favoriteIds(), isEmpty);
    });

    test('VERİ KAYBI ÖNLEMİ: kaynak verisi yeniden yazılınca favori ve geçmiş korunur', () {
      final p = remote('1');
      db.setFavorite(p, true);
      db.addVisit(p);
      db.setRating(p, 5);
      db.upsertParkings([remote('1', lat: 41.031)]); // REPLACE kullanılsaydı kaskadla silinirdi
      expect(db.favoriteIds(), {'osm:node/1'});
      expect(db.visits().length, 1);
      expect(db.ratings()['osm:node/1'], 5);
      expect(db.parking('osm:node/1')!.location.lat, 41.031);
    });

    test('önbellek temizliği favoriye bağlı kaydı silmez', () {
      final old = DateTime.now().toUtc().subtract(const Duration(days: 60));
      db.upsertParkings([remote('1', fetched: old), remote('2', fetched: old), remote('3')]);
      db.setFavorite(db.parking('osm:node/1')!, true);
      final removed = db.pruneCache();
      expect(removed, 1);
      expect(db.parking('osm:node/1'), isNotNull);
      expect(db.parking('osm:node/2'), isNull);
      expect(db.parking('osm:node/3'), isNotNull);
    });
  });

  group('Puan, son görüntülenen, ziyaret', () {
    test('puan 1–5, 0 kaldırır, aralık dışı reddedilir', () {
      final p = remote('1');
      db.setRating(p, 3);
      expect(db.ratings(), {'osm:node/1': 3});
      db.setRating(p, 0);
      expect(db.ratings(), isEmpty);
      expect(() => db.setRating(p, 6), throwsRangeError);
    });

    test('son görüntülenenler en fazla ${AppDatabase.recentLimit} kayıt tutar', () {
      for (var i = 0; i < AppDatabase.recentLimit + 5; i++) {
        db.recordView(remote('$i'));
      }
      expect(db.recent().length, AppDatabase.recentLimit);
      db.clearRecent();
      expect(db.recent(), isEmpty);
    });

    test('ziyaret ekle / sil / temizle', () {
      final id = db.addVisit(remote('1'), note: 'iş');
      db.addVisit(remote('2'));
      expect(db.visits().length, 2);
      db.deleteVisit(id);
      expect(db.visits().single.$2.id, 'osm:node/2');
      db.clearVisits();
      expect(db.visits(), isEmpty);
    });
  });

  group('Yerel yönetim', () {
    test('ekle, düzenle (fiyat + kapasite güncelle), kaynak notu', () {
      db.saveLocal(local('a', capacity: 50, hourly: 30), sourceNote: 'İşletme beyanı');
      db.saveLocal(local('a', capacity: 80, hourly: 45), sourceNote: 'Güncel tarife');
      final p = db.parking('local:a')!;
      expect(p.capacity, 80);
      expect(p.price!.hourly, 45);
      expect(db.sourceNote('local:a'), 'Güncel tarife');
      expect(db.localParkings().length, 1);
    });

    test('fiyat alanları temizlenince eski fiyat kalmaz', () {
      db.saveLocal(local('a', hourly: 30), sourceNote: 'x');
      db.saveLocal(local('a'), sourceNote: 'x');
      expect(db.parking('local:a')!.price, isNull);
    });

    test('silme: bağlı kayıtlar sayılır ve kaskadla silinir', () {
      final p = local('a');
      db.saveLocal(p, sourceNote: 'x');
      db.setFavorite(p, true);
      db.addVisit(p);
      db.addVisit(p);
      expect(db.dependentsOf(p.id), (favorites: 1, visits: 2, ratings: 0));
      db.deleteLocal(p.id);
      expect(db.parking(p.id), isNull);
      expect(db.favoriteIds(), isEmpty);
      expect(db.visits(), isEmpty);
    });

    test('uzak kaynaklı kayıtlar yönetim ekranından değiştirilemez/silinemez', () {
      expect(() => db.saveLocal(remote('1'), sourceNote: 'x'), throwsArgumentError);
      expect(() => db.deleteLocal('osm:node/1'), throwsArgumentError);
    });

    test('CHECK kısıtları geçersiz veriyi reddeder ve işlem geri alınır', () {
      const bad = Parking(id: 'osm:node/x', sourceId: 'osm', name: 'Hatalı', location: GeoPoint(95, 0));
      expect(() => db.upsertParkings([remote('ok'), bad]), throwsA(anything));
      expect(db.parking('osm:node/ok'), isNull, reason: 'işlem bütün olarak geri alındı');
    });
  });

  test('ayarlar', () {
    db.setSetting('tile_source', 'osm');
    expect(db.setting('tile_source'), 'osm');
    db.setSetting('tile_source', 'carto');
    expect(db.setting('tile_source'), 'carto');
    expect(db.setting('yok'), isNull);
  });

  test('kişisel verileri sıfırla yerel otoparkları korur', () {
    db.saveLocal(local('a'), sourceNote: 'x');
    db.setFavorite(remote('1'), true);
    db.recordView(remote('2'));
    db.resetUserData();
    expect(db.favoriteIds(), isEmpty);
    expect(db.recent(), isEmpty);
    expect(db.localParkings().length, 1);
  });

  test('dosya veritabanı: kapatıp açınca veriler kalıcı', () {
    final dir = Directory.systemTemp.createTempSync('parksense');
    final path = '${dir.path}/t.db';
    final a = AppDatabase.open(path);
    a.setFavorite(remote('1'), true);
    a.close();
    final b = AppDatabase.open(path);
    expect(b.favoriteIds(), {'osm:node/1'});
    b.close();
    dir.deleteSync(recursive: true);
  });

  test('çevredeki kayıtlar sorgusu', () {
    db.upsertParkings([remote('near', lat: 41.0371, lng: 28.9851), remote('far', lat: 41.2, lng: 29.2)]);
    final r = db.parkingsNear(const GeoPoint(41.0369, 28.9850), 1000);
    expect(r.map((p) => p.id), ['osm:node/near']);
  });
}
