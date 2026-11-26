import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/failure.dart';
import '../core/geo.dart';
import '../data/db/app_database.dart';
import '../data/parking_repository.dart';
import '../data/providers/geocoding.dart';
import '../data/providers/parking_provider.dart';
import '../app/app_info.dart';
import '../domain/filters.dart';
import '../domain/parking.dart';
import '../services/location_service.dart';
import '../services/navigation_service.dart';

enum LoadPhase { idle, loading, ready, error }

enum TileSource {
  carto('CARTO Voyager (önerilen)'),
  osm('OpenStreetMap Standart');

  const TileSource(this.label);
  final String label;
}

/// Uygulama durumu. Arayüz yalnızca bu sınıfı dinler; veri erişimi
/// depo (repository) ve servisler üzerinden yapılır.
class AppController extends ChangeNotifier {
  AppController({
    required this.db,
    required this.repo,
    LocationService? location,
    GeocodingService? geocoding,
    this.nav = const NavigationService(),
  }) : location = location ?? LocationService(),
       geocoding = geocoding ?? GeocodingService();

  final AppDatabase db;
  final ParkingRepository repo;
  final LocationService location;
  final GeocodingService geocoding;
  final NavigationService nav;

  // ----------------------------------------------------------------- konum
  LocationStatus locationStatus = LocationStatus.unknown;
  GeoPoint? center;
  String centerLabel = '';
  bool centerIsUser = false;
  bool locating = false;

  // ----------------------------------------------------------------- veri
  LoadPhase phase = LoadPhase.idle;
  AppFailure? failure;
  List<String> warnings = const [];
  bool fromCache = false;
  DateTime? loadedAt;
  SearchArea? loadedArea;
  List<Parking> all = const [];
  Map<String, int> counts = const {};

  // ----------------------------------------------------------------- tercih
  ParkingFilter _filter = ParkingFilter.none;
  ParkingFilter get filter => _filter;
  double baseRadiusM = 3000;
  static const maxRadiusM = 10000.0;
  TileSource tileSource = TileSource.carto;
  String updateEndpoint = AppInfo.defaultUpdateEndpoint;

  Set<String> favoriteIds = {};
  Map<String, int> ratings = {};

  /// Masaüstünde seçili otopark (harita + detay paneli).
  final selected = ValueNotifier<Parking?>(null);

  /// Haritaya "buraya git" isteği (konum/yer değiştiğinde).
  final cameraRequest = ValueNotifier<(GeoPoint, double)?>(null);

  List<Parking>? _visibleCache;

  void init() {
    tileSource = TileSource.values.firstWhere((t) => t.name == db.setting('tile_source'), orElse: () => TileSource.carto);
    baseRadiusM = double.tryParse(db.setting('radius_m') ?? '') ?? 3000;
    final ep = db.setting('update_endpoint');
    if (ep != null) updateEndpoint = ep;
    favoriteIds = db.favoriteIds();
    ratings = db.ratings();
    try {
      db.pruneCache();
    } catch (_) {}
    notifyListeners();
  }

  double get searchRadiusM => math.min(maxRadiusM, math.max(baseRadiusM, _filter.maxDistanceM ?? 0));

  /// Filtrelenmiş ve sıralanmış sonuçlar (önbelleklenir).
  List<Parking> get visible => _visibleCache ??= _filter.apply(all, origin: center);

  double? distanceTo(Parking p) => center == null ? null : Geo.distanceM(center!, p.location);

  List<Parking> get nearby {
    if (center == null) return const [];
    final l = [...all]..sort((a, b) => distanceTo(a)!.compareTo(distanceTo(b)!));
    return l.take(8).toList();
  }

  /// Öne çıkanlar: ölçüt şeffaftır ve arayüzde yazılır.
  (List<Parking>, String) get featured {
    final live = all.where((p) => p.hasLiveOccupancy && p.isOpenNow != false && !p.occupancy!.isFull).toList()
      ..sort((a, b) => b.occupancy!.free.compareTo(a.occupancy!.free));
    if (live.length >= 3) return (live.take(6).toList(), 'Anlık verisi olan ve en çok boş yeri bulunan otoparklar');
    final priced = all.where((p) => p.price?.effectiveHourly != null && !p.nameIsGenerated).toList()
      ..sort((a, b) => a.price!.effectiveHourly!.compareTo(b.price!.effectiveHourly!));
    if (priced.isNotEmpty) return (priced.take(6).toList(), 'Fiyat bilgisi bulunan, saatlik ücreti en uygun otoparklar');
    final withCap = all.where((p) => p.totalCapacity != null && !p.nameIsGenerated).toList()
      ..sort((a, b) => b.totalCapacity!.compareTo(a.totalCapacity!));
    return (withCap.take(6).toList(), 'Kapasite bilgisi bulunan en büyük otoparklar');
  }

  void _changed() {
    _visibleCache = null;
    notifyListeners();
  }

  // ------------------------------------------------------------ konum / yer

  /// İzin zaten verilmişse sessizce konumu kullanır (açılışta). İzin istemez.
  Future<void> tryAutoLocate() async {
    try {
      final res = await location.currentIfGranted().timeout(const Duration(seconds: 20));
      if (res.status == LocationStatus.granted && res.point != null) {
        locationStatus = res.status;
        await setCenter(res.point!, 'Konumunuz', isUser: true);
      } else {
        locationStatus = res.status;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<LocationStatus> useMyLocation() async {
    locating = true;
    notifyListeners();
    final res = await location.current();
    locating = false;
    locationStatus = res.status;
    if (res.status == LocationStatus.granted && res.point != null) {
      await setCenter(res.point!, 'Konumunuz', isUser: true);
    } else {
      notifyListeners();
    }
    return res.status;
  }

  Future<List<PlaceResult>> searchPlaces(String query) => geocoding.search(query);

  Future<void> selectPlace(PlaceResult place) =>
      setCenter(place.point, place.detail.isEmpty ? place.name : '${place.name}, ${place.detail.split(',').first}');

  Future<void> setCenter(GeoPoint p, String label, {bool isUser = false, double zoom = 15}) async {
    center = p;
    centerLabel = label;
    centerIsUser = isUser;
    selected.value = null;
    cameraRequest.value = (p, zoom);
    _changed();
    await load();
  }

  /// Haritada "Bu bölgede ara".
  Future<void> searchHere(GeoPoint p) async {
    center = p;
    centerLabel = 'Harita bölgesi';
    centerIsUser = false;
    _changed();
    await load();
  }

  // ------------------------------------------------------------------ yükle

  Future<void> load({bool force = false}) async {
    final c = center;
    if (c == null) return;
    if (force) repo.clearMemoryCaches();
    phase = LoadPhase.loading;
    failure = null;
    notifyListeners();
    try {
      final area = SearchArea(c, searchRadiusM);
      final out = await repo.search(area);
      if (center != c) return; // Bu arada başka bir arama başladı.
      all = out.items;
      counts = out.counts;
      warnings = out.warnings;
      fromCache = out.fromCache;
      loadedArea = area;
      loadedAt = DateTime.now();
      phase = LoadPhase.ready;
      if (out.fromCache && out.items.isEmpty) {
        failure = const AppFailure(FailureKind.offline);
        phase = LoadPhase.error;
      }
    } catch (e) {
      failure = AppFailure.from(e);
      phase = LoadPhase.error;
    }
    _changed();
  }

  void setFilter(ParkingFilter f) {
    final needsWider = (f.maxDistanceM ?? 0) > (loadedArea?.radiusM ?? double.infinity);
    _filter = f;
    _changed();
    if (needsWider) load();
  }

  void setQuery(String q) => setFilter(_filter.copyWith(query: q));

  /// Yüklü listedeki en güncel hâli (anlık doluluk dâhil).
  Parking live(Parking p) => all.firstWhere((x) => x.id == p.id, orElse: () => p);

  Future<Parking> details(Parking p) async {
    try {
      final rich = await repo.details(p);
      final i = all.indexWhere((x) => x.id == rich.id);
      if (i >= 0) {
        all = [...all]..[i] = rich;
        _changed();
      }
      return rich;
    } catch (_) {
      return live(p);
    }
  }

  // ------------------------------------------------------ kullanıcı verisi

  bool isFavorite(Parking p) => favoriteIds.contains(p.id);

  void toggleFavorite(Parking p) {
    final on = !isFavorite(p);
    db.setFavorite(p, on);
    favoriteIds = db.favoriteIds();
    notifyListeners();
  }

  void rate(Parking p, int stars) {
    db.setRating(p, stars);
    ratings = db.ratings();
    notifyListeners();
  }

  void recordView(Parking p) {
    try {
      db.recordView(p);
    } catch (_) {}
  }

  void recordVisit(Parking p, {String? note}) {
    db.addVisit(p, note: note);
    notifyListeners();
  }

  Future<NavResult> navigate(Parking p) => nav.navigate(p.location);

  // --------------------------------------------------------- yerel yönetim

  void saveLocal(Parking p, String sourceNote) {
    db.saveLocal(p, sourceNote: sourceNote);
    final saved = db.parking(p.id)!;
    final i = all.indexWhere((x) => x.id == p.id);
    final inArea = center != null && Geo.distanceM(center!, saved.location) <= (loadedArea?.radiusM ?? 0);
    if (i >= 0) {
      all = [...all]..removeAt(i);
    }
    if (inArea) all = [...all, saved];
    _changed();
  }

  void deleteLocal(String id) {
    db.deleteLocal(id);
    all = all.where((p) => p.id != id).toList();
    favoriteIds = db.favoriteIds();
    ratings = db.ratings();
    if (selected.value?.id == id) selected.value = null;
    _changed();
  }

  /// Veritabanında doğrudan yapılan değişikliklerden sonra arayüzü tazeler.
  void touch() => notifyListeners();

  // ------------------------------------------------------------- ayarlar

  void setTileSource(TileSource t) {
    tileSource = t;
    db.setSetting('tile_source', t.name);
    notifyListeners();
  }

  void setBaseRadius(double m) {
    baseRadiusM = m;
    db.setSetting('radius_m', m.toStringAsFixed(0));
    notifyListeners();
    load();
  }

  void setUpdateEndpoint(String v) {
    updateEndpoint = v.trim();
    db.setSetting('update_endpoint', updateEndpoint);
    notifyListeners();
  }

  int clearCache() {
    repo.clearMemoryCaches();
    return db.clearRemoteCache();
  }

  void resetUserData() {
    db.resetUserData();
    favoriteIds = {};
    ratings = {};
    notifyListeners();
  }

  @override
  void dispose() {
    selected.dispose();
    cameraRequest.dispose();
    super.dispose();
  }
}
