import '../core/failure.dart';
import '../core/geo.dart';
import '../domain/data_source.dart';
import '../domain/parking.dart';
import 'db/app_database.dart';
import 'providers/ispark_provider.dart';
import 'providers/osm_provider.dart';
import 'providers/parking_provider.dart';

class SearchOutcome {
  const SearchOutcome({required this.items, required this.area, this.warnings = const [], this.fromCache = false, this.counts = const {}});

  final List<Parking> items;
  final SearchArea area;

  /// Kullanıcıya gösterilecek kaynak uyarıları (ör. İSPARK'a ulaşılamadı).
  final List<String> warnings;

  /// Tüm uzak kaynaklar başarısız oldu, cihazdaki önbellek gösteriliyor.
  final bool fromCache;
  final Map<String, int> counts;
}

/// Sağlayıcıları birleştiren tek giriş noktası: paralel sorgu, tekrarları
/// ayıklama, yerel kayıtlar, önbellek ve çevrimdışı yedek.
class ParkingRepository {
  ParkingRepository({required this.db, IsparkProvider? ispark, OsmProvider? osm})
    : ispark = ispark ?? IsparkProvider(),
      osm = osm ?? OsmProvider();

  final AppDatabase db;
  final IsparkProvider ispark;
  final OsmProvider osm;

  List<ParkingProvider> get remoteProviders => [ispark, osm];

  /// İki kaynakta aynı otopark varsa (bu mesafeden yakın) resmî kaynak tutulur.
  static const duplicateRadiusM = 40.0;

  Future<SearchOutcome> search(SearchArea area) async {
    final active = remoteProviders.where((p) => p.covers(area)).toList();
    final results = await Future.wait(
      active.map((p) async {
        try {
          return (p, await p.fetch(area), null as AppFailure?);
        } catch (e) {
          return (p, null as ProviderResult?, AppFailure.from(e, source: p.info.name));
        }
      }),
    );

    final warnings = <String>[];
    final remote = <Parking>[];
    for (final (provider, result, failure) in results) {
      if (result != null) {
        remote.addAll(result.items);
      } else {
        warnings.add('${provider.info.name}: ${failure!.message}');
      }
    }
    final anySuccess = results.any((r) => r.$2 != null);
    final local = db.parkingsNear(area.center, area.radiusM, sourceIds: {DataSources.local.id});

    if (active.isNotEmpty && !anySuccess) {
      // Çevrimdışı yedek: cihazdaki önbellek; doluluk bilgisi İÇERMEZ.
      final cached = db.parkingsNear(area.center, area.radiusM).where((p) => !p.isLocal).toList();
      final items = dedupe([...cached, ...local]);
      return SearchOutcome(items: items, area: area, warnings: warnings, fromCache: true, counts: _count(items));
    }

    final items = dedupe([...remote, ...local]);
    if (remote.isNotEmpty) {
      try {
        db.upsertParkings(remote.where((p) => items.contains(p)));
      } catch (_) {
        // Önbelleğe yazılamaması aramayı bozmaz.
      }
    }
    return SearchOutcome(items: items, area: area, warnings: warnings, counts: _count(items));
  }

  static Map<String, int> _count(List<Parking> items) {
    final m = <String, int>{};
    for (final p in items) {
      m[p.sourceId] = (m[p.sourceId] ?? 0) + 1;
    }
    return m;
  }

  /// OSM kaydı bir İSPARK kaydına [duplicateRadiusM]'den yakınsa düşürülür.
  static List<Parking> dedupe(List<Parking> items) {
    final official = items.where((p) => p.source.reliability == Reliability.official).toList();
    final seen = <String>{};
    final out = <Parking>[];
    for (final p in items) {
      if (!seen.add(p.id)) continue;
      if (p.source.reliability == Reliability.community && official.any((o) => Geo.distanceM(o.location, p.location) < duplicateRadiusM)) {
        continue;
      }
      out.add(p);
    }
    return out;
  }

  /// Detay ekranı için en güncel bilgi (İSPARK'ta tarife + resmî güncelleme zamanı).
  Future<Parking> details(Parking p, {bool force = false}) async {
    if (p.sourceId == DataSources.ispark.id) {
      final rich = await ispark.enrich(p, force: force);
      try {
        db.upsertParkings([rich]);
      } catch (_) {}
      return rich;
    }
    if (p.isLocal) return db.parking(p.id) ?? p;
    return p;
  }

  void clearMemoryCaches() {
    ispark.clearCache();
    osm.clearCache();
  }
}
