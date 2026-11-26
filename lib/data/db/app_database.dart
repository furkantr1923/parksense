import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../../core/geo.dart';
import '../../domain/data_source.dart';
import '../../domain/parking.dart';

class VisitEntry {
  const VisitEntry({required this.id, required this.parkingId, required this.visitedAt, this.note});

  final int id;
  final String parkingId;
  final DateTime visitedAt;
  final String? note;
}

/// Yerel SQLite veritabanı.
///
/// Tablolar: Parking, ParkingPrice, ParkingRating, Favorite, RecentParking,
/// VisitHistory, DataSource, AppSettings. İlişkiler yabancı anahtarlarla
/// (ON DELETE CASCADE) kurulur ve `PRAGMA foreign_keys = ON` ile zorlanır.
///
/// Veri kaybına karşı önlemler:
/// - Uzak kaynaklardan gelen kayıtlar `INSERT … ON CONFLICT DO UPDATE` ile
///   güncellenir. `INSERT OR REPLACE` KULLANILMAZ, çünkü REPLACE satırı silip
///   yeniden ekler ve kaskad silme ile favorileri/geçmişi yok ederdi.
/// - Çok adımlı yazmalar tek bir işlem (transaction) içinde yapılır.
/// - Önbellek temizliği favori, geçmiş, puan veya yerel kayıtlara dokunmaz.
/// - Şema sürümü `PRAGMA user_version` ile yönetilir; geçişler sıralı uygulanır.
class AppDatabase {
  AppDatabase._(this._db) {
    _db.execute('PRAGMA foreign_keys = ON;');
    _db.execute('PRAGMA journal_mode = WAL;');
    _db.execute('PRAGMA synchronous = NORMAL;');
    _migrate();
  }

  factory AppDatabase.open(String path) => AppDatabase._(sqlite3.open(path));

  factory AppDatabase.inMemory() => AppDatabase._(sqlite3.openInMemory());

  final Database _db;

  static const schemaVersion = 1;

  int get userVersion => _db.select('PRAGMA user_version;').first.columnAt(0) as int;

  bool get foreignKeysOn => (_db.select('PRAGMA foreign_keys;').first.columnAt(0) as int) == 1;

  void close() => _db.close();

  void _migrate() {
    final v = userVersion;
    if (v >= schemaVersion) return;
    _tx(() {
      if (v < 1) {
        _db.execute('''
          CREATE TABLE IF NOT EXISTS DataSource (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            url TEXT NOT NULL,
            license TEXT NOT NULL,
            reliability TEXT NOT NULL,
            realtime INTEGER NOT NULL DEFAULT 0,
            description TEXT NOT NULL
          );
          CREATE TABLE IF NOT EXISTS Parking (
            id TEXT PRIMARY KEY,
            source_id TEXT NOT NULL REFERENCES DataSource(id),
            name TEXT NOT NULL,
            address TEXT,
            city TEXT,
            district TEXT,
            lat REAL NOT NULL CHECK (lat BETWEEN -90 AND 90),
            lng REAL NOT NULL CHECK (lng BETWEEN -180 AND 180),
            type TEXT NOT NULL,
            capacity INTEGER CHECK (capacity IS NULL OR capacity >= 0),
            opening_hours TEXT,
            is_open INTEGER,
            phone TEXT,
            website TEXT,
            accessibility TEXT,
            operator TEXT,
            source_note TEXT,
            extra TEXT NOT NULL DEFAULT '{}',
            is_local INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT,
            fetched_at TEXT
          );
          CREATE INDEX IF NOT EXISTS idx_parking_geo ON Parking(lat, lng);
          CREATE INDEX IF NOT EXISTS idx_parking_local ON Parking(is_local);
          CREATE TABLE IF NOT EXISTS ParkingPrice (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            parking_id TEXT NOT NULL REFERENCES Parking(id) ON DELETE CASCADE,
            kind TEXT NOT NULL CHECK (kind IN ('hourly','daily','monthly','tier','free_minutes','is_free','raw')),
            label TEXT,
            amount REAL CHECK (amount IS NULL OR amount >= 0),
            text_value TEXT,
            source_id TEXT NOT NULL REFERENCES DataSource(id),
            updated_at TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0
          );
          CREATE INDEX IF NOT EXISTS idx_price_parking ON ParkingPrice(parking_id);
          CREATE TABLE IF NOT EXISTS ParkingRating (
            parking_id TEXT PRIMARY KEY REFERENCES Parking(id) ON DELETE CASCADE,
            stars INTEGER NOT NULL CHECK (stars BETWEEN 1 AND 5),
            updated_at TEXT NOT NULL
          );
          CREATE TABLE IF NOT EXISTS Favorite (
            parking_id TEXT PRIMARY KEY REFERENCES Parking(id) ON DELETE CASCADE,
            created_at TEXT NOT NULL
          );
          CREATE TABLE IF NOT EXISTS RecentParking (
            parking_id TEXT PRIMARY KEY REFERENCES Parking(id) ON DELETE CASCADE,
            viewed_at TEXT NOT NULL
          );
          CREATE TABLE IF NOT EXISTS VisitHistory (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            parking_id TEXT NOT NULL REFERENCES Parking(id) ON DELETE CASCADE,
            visited_at TEXT NOT NULL,
            note TEXT
          );
          CREATE INDEX IF NOT EXISTS idx_visit_time ON VisitHistory(visited_at);
          CREATE TABLE IF NOT EXISTS AppSettings (
            key TEXT PRIMARY KEY,
            value TEXT
          );
        ''');
      }
      for (final s in DataSources.all) {
        _db.execute(
          'INSERT INTO DataSource(id,name,url,license,reliability,realtime,description) VALUES (?,?,?,?,?,?,?) '
          'ON CONFLICT(id) DO UPDATE SET name=excluded.name, url=excluded.url, license=excluded.license, '
          'reliability=excluded.reliability, realtime=excluded.realtime, description=excluded.description',
          [s.id, s.name, s.url, s.license, s.reliability.name, s.realtimeOccupancy ? 1 : 0, s.description],
        );
      }
      _db.execute('PRAGMA user_version = $schemaVersion;');
    });
  }

  T _tx<T>(T Function() body) {
    _db.execute('BEGIN IMMEDIATE;');
    try {
      final r = body();
      _db.execute('COMMIT;');
      return r;
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();

  // ------------------------------------------------------------- otoparklar

  /// Uzak ve yerel kayıtları güvenle yazar (favoriler/geçmiş korunur).
  void upsertParkings(Iterable<Parking> items, {String? sourceNote}) {
    _tx(() {
      for (final p in items) {
        _upsert(p, sourceNote: sourceNote);
      }
    });
  }

  void _upsert(Parking p, {String? sourceNote}) {
    final extra = jsonEncode({
      'photos': p.photos,
      'amenities': p.amenities,
      if (p.accessNote != null) 'accessNote': p.accessNote,
      if (p.sourceRef != null) 'sourceRef': p.sourceRef,
      if (p.nameIsGenerated) 'nameGenerated': true,
    });
    _db.execute(
      '''
      INSERT INTO Parking(id,source_id,name,address,city,district,lat,lng,type,capacity,opening_hours,is_open,
                          phone,website,accessibility,operator,source_note,extra,is_local,updated_at,fetched_at)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET
        source_id=excluded.source_id, name=excluded.name, address=COALESCE(excluded.address, Parking.address),
        city=excluded.city, district=COALESCE(excluded.district, Parking.district), lat=excluded.lat, lng=excluded.lng,
        type=excluded.type, capacity=excluded.capacity, opening_hours=excluded.opening_hours, is_open=excluded.is_open,
        phone=excluded.phone, website=excluded.website, accessibility=excluded.accessibility, operator=excluded.operator,
        source_note=COALESCE(excluded.source_note, Parking.source_note), extra=excluded.extra, is_local=excluded.is_local,
        updated_at=excluded.updated_at, fetched_at=excluded.fetched_at
    ''',
      [
        p.id,
        p.sourceId,
        p.name,
        p.address,
        p.city,
        p.district,
        p.location.lat,
        p.location.lng,
        p.type.name,
        p.capacity,
        p.openingHours,
        p.isOpenNow == null ? null : (p.isOpenNow! ? 1 : 0),
        p.phone,
        p.website,
        p.accessibility,
        p.operatorName,
        sourceNote,
        extra,
        p.isLocal ? 1 : 0,
        p.updatedAt?.toIso8601String(),
        p.fetchedAt?.toIso8601String(),
      ],
    );
    final price = p.price;
    final full = price != null && (price.hasAnyAmount || price.rawText != null || price.isFree != null);
    if (!p.isLocal && !full) {
      // Kısmi bilgi (ör. İSPARK listesi yalnızca ücretsiz süreyi verir):
      // daha önce alınmış ayrıntılı tarife silinmez.
      if (price?.freeMinutes != null) {
        _db.execute("DELETE FROM ParkingPrice WHERE parking_id=? AND kind='free_minutes'", [p.id]);
        _insertPrice(p.id, price!, 'free_minutes', null, price.freeMinutes!.toDouble(), null, 99);
      }
      return;
    }
    _db.execute('DELETE FROM ParkingPrice WHERE parking_id=?', [p.id]);
    if (price == null) return;
    var order = 0;
    if (price.hourly != null) _insertPrice(p.id, price, 'hourly', null, price.hourly, null, order++);
    if (price.daily != null) _insertPrice(p.id, price, 'daily', null, price.daily, null, order++);
    if (price.monthly != null) _insertPrice(p.id, price, 'monthly', null, price.monthly, null, order++);
    for (final t in price.tiers) {
      _insertPrice(p.id, price, 'tier', t.label, t.amount, null, order++);
    }
    if (price.freeMinutes != null) _insertPrice(p.id, price, 'free_minutes', null, price.freeMinutes!.toDouble(), null, order++);
    if (price.isFree != null) _insertPrice(p.id, price, 'is_free', null, null, price.isFree! ? '1' : '0', order++);
    if (price.rawText != null) _insertPrice(p.id, price, 'raw', null, null, price.rawText, order++);
  }

  void _insertPrice(String id, PriceInfo p, String kind, String? label, double? amount, String? text, int order) {
    _db.execute(
      'INSERT INTO ParkingPrice(parking_id,kind,label,amount,text_value,source_id,updated_at,sort_order) VALUES (?,?,?,?,?,?,?,?)',
      [id, kind, label, amount, text, p.sourceId, p.updatedAt?.toIso8601String(), order],
    );
  }

  PriceInfo? _priceFor(String id) {
    final rows = _db.select('SELECT * FROM ParkingPrice WHERE parking_id=? ORDER BY sort_order', [id]);
    if (rows.isEmpty) return null;
    double? hourly, daily, monthly;
    int? freeMinutes;
    bool? isFree;
    String? raw;
    final tiers = <PriceTier>[];
    final sourceId = rows.first['source_id'] as String;
    final updated = DateTime.tryParse('${rows.first['updated_at']}');
    for (final r in rows) {
      final amount = (r['amount'] as num?)?.toDouble();
      switch (r['kind']) {
        case 'hourly':
          hourly = amount;
        case 'daily':
          daily = amount;
        case 'monthly':
          monthly = amount;
        case 'tier':
          if (amount != null) tiers.add(PriceTier(r['label'] as String? ?? '', amount));
        case 'free_minutes':
          freeMinutes = amount?.round();
        case 'is_free':
          isFree = r['text_value'] == '1';
        case 'raw':
          raw = r['text_value'] as String?;
      }
    }
    final info = PriceInfo(
      hourly: hourly,
      daily: daily,
      monthly: monthly,
      tiers: tiers,
      freeMinutes: freeMinutes,
      isFree: isFree,
      rawText: raw,
      sourceId: sourceId,
      updatedAt: updated,
    );
    return info.hasAny ? info : null;
  }

  /// Veritabanından okunan kayıtlarda doluluk YOKTUR: doluluk yalnızca
  /// kaynaktan yeni alınmış veriyle gösterilir, eski değer "anlık" sanılmasın.
  Parking _row(Row r) {
    final extra = jsonDecode(r['extra'] as String? ?? '{}') as Map<String, dynamic>;
    final id = r['id'] as String;
    final isOpen = r['is_open'] as int?;
    return Parking(
      id: id,
      sourceId: r['source_id'] as String,
      name: r['name'] as String,
      nameIsGenerated: extra['nameGenerated'] == true,
      location: GeoPoint((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()),
      address: r['address'] as String?,
      city: r['city'] as String?,
      district: r['district'] as String?,
      type: ParkingType.parse(r['type'] as String?),
      capacity: r['capacity'] as int?,
      openingHours: r['opening_hours'] as String?,
      isOpenNow: isOpen == null ? null : isOpen == 1,
      phone: r['phone'] as String?,
      website: r['website'] as String?,
      accessibility: r['accessibility'] as String?,
      operatorName: r['operator'] as String?,
      photos: (extra['photos'] as List?)?.cast<String>() ?? const [],
      amenities: (extra['amenities'] as List?)?.cast<String>() ?? const [],
      accessNote: extra['accessNote'] as String?,
      sourceRef: extra['sourceRef'] as String?,
      price: _priceFor(id),
      updatedAt: DateTime.tryParse('${r['updated_at']}'),
      fetchedAt: DateTime.tryParse('${r['fetched_at']}'),
    );
  }

  Parking? parking(String id) {
    final rows = _db.select('SELECT * FROM Parking WHERE id=?', [id]);
    return rows.isEmpty ? null : _row(rows.first);
  }

  String? sourceNote(String id) {
    final rows = _db.select('SELECT source_note FROM Parking WHERE id=?', [id]);
    return rows.isEmpty ? null : rows.first['source_note'] as String?;
  }

  int get parkingCount => _db.select('SELECT COUNT(*) c FROM Parking').first['c'] as int;

  /// Önbellekteki kayıtlar (çevrimdışı yedek). [sourceIds] boşsa tümü.
  List<Parking> parkingsNear(GeoPoint center, double radiusM, {Set<String> sourceIds = const {}}) {
    final dLat = radiusM / 111320.0;
    final dLng = radiusM / 85000.0; // Türkiye enlemleri için güvenli üst sınır
    final rows = _db.select('SELECT * FROM Parking WHERE lat BETWEEN ? AND ? AND lng BETWEEN ? AND ?', [
      center.lat - dLat,
      center.lat + dLat,
      center.lng - dLng,
      center.lng + dLng,
    ]);
    return rows
        .map(_row)
        .where((p) => sourceIds.isEmpty || sourceIds.contains(p.sourceId))
        .where((p) => Geo.distanceM(center, p.location) <= radiusM)
        .toList();
  }

  List<Parking> localParkings() => _db.select('SELECT * FROM Parking WHERE is_local=1 ORDER BY name COLLATE NOCASE').map(_row).toList();

  /// Yerel kayıt ekler/günceller. Uzak kaynaklı kimliklere yazmayı reddeder.
  void saveLocal(Parking p, {required String sourceNote}) {
    if (!p.isLocal || !p.id.startsWith('local:')) {
      throw ArgumentError('Yalnızca yerel kayıtlar düzenlenebilir: ${p.id}');
    }
    _tx(() => _upsert(p, sourceNote: sourceNote));
  }

  /// Yerel kaydı siler; ilişkili favori, puan ve geçmiş kayıtları kaskadla silinir.
  /// Kaç ilişkili kaydın etkileneceği önce [dependentsOf] ile kullanıcıya gösterilir.
  void deleteLocal(String id) {
    if (!id.startsWith('local:')) throw ArgumentError('Uzak kaynaklı kayıt silinemez: $id');
    _tx(() => _db.execute('DELETE FROM Parking WHERE id=? AND is_local=1', [id]));
  }

  ({int favorites, int visits, int ratings}) dependentsOf(String id) {
    int c(String t) => _db.select('SELECT COUNT(*) c FROM $t WHERE parking_id=?', [id]).first['c'] as int;
    return (favorites: c('Favorite'), visits: c('VisitHistory'), ratings: c('ParkingRating'));
  }

  /// Hiçbir kullanıcı verisinin bağlı olmadığı eski uzak önbellek kayıtlarını siler.
  int pruneCache({Duration olderThan = const Duration(days: 30)}) {
    final cutoff = DateTime.now().toUtc().subtract(olderThan).toIso8601String();
    _db.execute(
      '''
      DELETE FROM Parking WHERE is_local=0 AND (fetched_at IS NULL OR fetched_at < ?)
        AND id NOT IN (SELECT parking_id FROM Favorite)
        AND id NOT IN (SELECT parking_id FROM RecentParking)
        AND id NOT IN (SELECT parking_id FROM VisitHistory)
        AND id NOT IN (SELECT parking_id FROM ParkingRating)
    ''',
      [cutoff],
    );
    return _db.updatedRows;
  }

  /// "Önbelleği temizle": yalnızca bağımsız uzak kayıtlar silinir.
  int clearRemoteCache() => pruneCache(olderThan: Duration.zero);

  // ---------------------------------------------------------------- favoriler

  void setFavorite(Parking p, bool on) {
    _tx(() {
      if (on) {
        _upsert(p);
        _db.execute('INSERT INTO Favorite(parking_id,created_at) VALUES (?,?) ON CONFLICT(parking_id) DO NOTHING', [p.id, _now()]);
      } else {
        _db.execute('DELETE FROM Favorite WHERE parking_id=?', [p.id]);
      }
    });
  }

  Set<String> favoriteIds() => _db.select('SELECT parking_id FROM Favorite').map((r) => r['parking_id'] as String).toSet();

  List<Parking> favorites() =>
      _db.select('SELECT p.* FROM Favorite f JOIN Parking p ON p.id=f.parking_id ORDER BY f.created_at DESC').map(_row).toList();

  // ---------------------------------------------------------------- puanlar

  /// 1–5 yıldız; 0 puanı kaldırır.
  void setRating(Parking p, int stars) {
    if (stars < 0 || stars > 5) throw RangeError.range(stars, 0, 5, 'stars');
    _tx(() {
      if (stars == 0) {
        _db.execute('DELETE FROM ParkingRating WHERE parking_id=?', [p.id]);
      } else {
        _upsert(p);
        _db.execute(
          'INSERT INTO ParkingRating(parking_id,stars,updated_at) VALUES (?,?,?) '
          'ON CONFLICT(parking_id) DO UPDATE SET stars=excluded.stars, updated_at=excluded.updated_at',
          [p.id, stars, _now()],
        );
      }
    });
  }

  Map<String, int> ratings() => {
    for (final r in _db.select('SELECT parking_id, stars FROM ParkingRating')) r['parking_id'] as String: r['stars'] as int,
  };

  // ------------------------------------------------- son görüntülenenler

  static const recentLimit = 30;

  void recordView(Parking p) {
    _tx(() {
      _upsert(p);
      _db.execute(
        'INSERT INTO RecentParking(parking_id,viewed_at) VALUES (?,?) ON CONFLICT(parking_id) DO UPDATE SET viewed_at=excluded.viewed_at',
        [p.id, _now()],
      );
      _db.execute(
        'DELETE FROM RecentParking WHERE parking_id NOT IN (SELECT parking_id FROM RecentParking ORDER BY viewed_at DESC LIMIT ?)',
        [recentLimit],
      );
    });
  }

  List<(Parking, DateTime)> recent() => _db
      .select('SELECT p.*, r.viewed_at AS v FROM RecentParking r JOIN Parking p ON p.id=r.parking_id ORDER BY r.viewed_at DESC')
      .map((r) => (_row(r), DateTime.parse(r['v'] as String)))
      .toList();

  void clearRecent() => _tx(() => _db.execute('DELETE FROM RecentParking'));

  // ---------------------------------------------------------- ziyaret geçmişi

  int addVisit(Parking p, {String? note}) => _tx(() {
    _upsert(p);
    _db.execute('INSERT INTO VisitHistory(parking_id,visited_at,note) VALUES (?,?,?)', [p.id, _now(), note]);
    return _db.lastInsertRowId;
  });

  List<(VisitEntry, Parking)> visits() => _db
      .select(
        'SELECT v.id AS vid, v.visited_at, v.note, p.* FROM VisitHistory v JOIN Parking p ON p.id=v.parking_id ORDER BY v.visited_at DESC',
      )
      .map(
        (r) => (
          VisitEntry(
            id: r['vid'] as int,
            parkingId: r['id'] as String,
            visitedAt: DateTime.parse(r['visited_at'] as String),
            note: r['note'] as String?,
          ),
          _row(r),
        ),
      )
      .toList();

  void deleteVisit(int id) => _tx(() => _db.execute('DELETE FROM VisitHistory WHERE id=?', [id]));

  void clearVisits() => _tx(() => _db.execute('DELETE FROM VisitHistory'));

  // ---------------------------------------------------------------- ayarlar

  String? setting(String key) {
    final r = _db.select('SELECT value FROM AppSettings WHERE key=?', [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  void setSetting(String key, String? value) =>
      _db.execute('INSERT INTO AppSettings(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value', [key, value]);

  List<Map<String, Object?>> dataSourceRows() =>
      _db.select('SELECT * FROM DataSource ORDER BY id').map((r) => Map<String, Object?>.from(r)).toList();

  /// Tüm kullanıcı verisini siler (onaydan sonra çağrılır). Yerel otoparklar
  /// [includeLocal] true değilse korunur.
  void resetUserData({bool includeLocal = false}) => _tx(() {
    _db.execute('DELETE FROM Favorite');
    _db.execute('DELETE FROM RecentParking');
    _db.execute('DELETE FROM VisitHistory');
    _db.execute('DELETE FROM ParkingRating');
    if (includeLocal) _db.execute('DELETE FROM Parking WHERE is_local=1');
  });
}
