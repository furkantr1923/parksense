import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../app/app_info.dart';
import '../app/app_scope.dart';
import '../core/failure.dart';
import '../core/geo.dart';
import '../core/http.dart';
import '../data/providers/geocoding.dart';
import '../data/providers/osm_provider.dart';
import '../data/providers/parking_provider.dart';
import '../domain/data_source.dart';
import '../domain/filters.dart';
import '../domain/parking.dart';
import '../services/navigation_service.dart';
import '../services/update_service.dart';
import '../state/app_controller.dart';
import '../ui/shell.dart';

/// Öz-sınama ve ekran görüntüsü modu.
class CaptureConfig {
  const CaptureConfig({this.directory});

  /// Windows: görüntü ve raporun yazılacağı klasör. Android: null
  /// (görüntüleri CI, log işaretlerine bakarak `adb screencap` ile alır).
  final String? directory;

  static const _androidFlag = bool.fromEnvironment('PARKSENSE_CAPTURE');

  static CaptureConfig? fromArgs(List<String> args) {
    for (final a in args) {
      if (a.startsWith('--capture=')) return CaptureConfig(directory: a.substring('--capture='.length));
    }
    if (_androidFlag) return const CaptureConfig();
    return null;
  }
}

/// Derlenmiş uygulamayı GERÇEK veri kaynaklarıyla gezer, her ekranın
/// görüntüsünü alır ve sonuçları rapora yazar. Yalnızca CI'da kullanılır.
class CaptureRunner {
  CaptureRunner({required this.config, required this.controller, required this.shellKey, required this.boundaryKey});

  final CaptureConfig config;
  final AppController controller;
  final GlobalKey<AppShellState> shellKey;
  final GlobalKey boundaryKey;
  final _report = StringBuffer();
  int _step = 0;
  int _fails = 0;

  static const taksim = PlaceResult(name: 'Taksim', detail: 'Beyoğlu, İstanbul', point: GeoPoint(41.0369, 28.9850));
  static const kizilay = PlaceResult(name: 'Kızılay', detail: 'Çankaya, Ankara', point: GeoPoint(39.9208, 32.8541));

  void _log(String line) {
    _report.writeln(line);
    debugPrint('PARKSENSE_SELFTEST $line');
  }

  AppShellState get _shell => shellKey.currentState!;

  Future<void> run() async {
    final started = DateTime.now();
    _log(
      'PARKSENSE ${AppInfo.version} öz-sınama · ${DateTime.now().toUtc().toIso8601String()} · ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    await _shot('acilis_konum_izni_yok');

    await _probeSources();

    // ---- Gerçek akış: İstanbul / Taksim
    final t0 = DateTime.now();
    await controller.selectPlace(taksim);
    _log(
      'Taksim araması: ${DateTime.now().difference(t0).inMilliseconds} ms · ${controller.all.length} otopark · kaynaklar ${controller.counts} · uyarılar ${controller.warnings}',
    );
    final live = controller.all.where((p) => p.hasLiveOccupancy).toList();
    _log('${live.isNotEmpty ? 'OK  ' : 'FAIL'} Anlık doluluklu otopark sayısı (İSPARK): ${live.length}');
    if (live.isEmpty) _fails++;
    await Future<void>.delayed(const Duration(seconds: 2));

    _shell.open(Dest.home);
    await _wait(3);
    await _shot('ana_sayfa');
    _shell.open(Dest.map);
    await _wait(8);
    await _shot('harita');
    _shell.open(Dest.list);
    await _wait(2);
    await _shot('liste');

    // Filtreler birlikte: boş yeri olan + 2 km + boş yere göre sıralı
    final f = const ParkingFilter(occupancy: OccupancyFilter.hasSpace, maxDistanceM: 2000, sort: ParkingSort.freeSpaces);
    controller.setFilter(f);
    final expected = f.apply(controller.all, origin: controller.center);
    final ok =
        controller.visible.length == expected.length &&
        controller.visible.every((p) => p.hasLiveOccupancy && !p.occupancy!.isFull && Geo.distanceM(taksim.point, p.location) <= 2000);
    _log('${ok ? 'OK  ' : 'FAIL'} Birleşik filtre (boş yer + ≤2 km + sıralama): ${controller.visible.length} sonuç');
    if (!ok) _fails++;
    await _wait(2);
    await _shot('liste_filtreli');
    controller.setFilter(const ParkingFilter(types: {ParkingType.underground}, maxHourlyPrice: 1));
    await _wait(2);
    await _shot('filtre_sonuc_yok');
    controller.setFilter(ParkingFilter.none);

    // Detay: İSPARK (anlık doluluk + tarife)
    if (live.isNotEmpty) {
      final p = live.first;
      _openDetail(p);
      await _wait(6);
      final rich = controller.live(p);
      _log(
        'İSPARK detay: "${rich.name}" · tarife kademesi ${rich.price?.tiers.length ?? 0} · saatlik ${rich.price?.hourly} · aylık ${rich.price?.monthly} · ücretsiz ${rich.price?.freeMinutes} dk · adres ${rich.address != null}',
      );
      await _shot('detay_ispark');
      controller.toggleFavorite(rich);
      controller.rate(rich, 4);
      controller.recordVisit(rich);
    }
    final osm = controller.all.where((p) => p.sourceId == DataSources.osm.id && !p.nameIsGenerated).toList();
    if (osm.isNotEmpty) {
      _openDetail(osm.first);
      await _wait(4);
      await _shot('detay_osm');
      controller.toggleFavorite(osm.first);
    }
    _shell.open(Dest.favorites);
    await _wait(2);
    await _shot('favoriler');
    _shell.open(Dest.history);
    await _wait(2);
    await _shot('gecmis');

    // Yerel yönetim: kayıt ekle
    final local = Parking(
      id: 'local:selftest',
      sourceId: DataSources.local.id,
      name: 'Örnek Yerel Otopark (öz-sınama)',
      location: const GeoPoint(41.0375, 28.9862),
      type: ParkingType.open,
      city: 'İstanbul',
      district: 'Beyoğlu',
      capacity: 40,
      price: PriceInfo(hourly: 60, daily: 300, sourceId: DataSources.local.id, updatedAt: DateTime.now().toUtc()),
      updatedAt: DateTime.now().toUtc(),
    );
    controller.saveLocal(local, 'Öz-sınama kaydı');
    _shell.open(Dest.manage);
    await _wait(2);
    await _shot('yonetim');

    await _dbChecks();

    _shell.open(Dest.settings);
    await _wait(2);
    await _shot('ayarlar');
    _shell.open(Dest.about);
    await _wait(2);
    await _shot('hakkinda');

    // ---- İstanbul dışı: yalnızca OSM, doluluk yok
    await controller.selectPlace(kizilay);
    _log(
      'Kızılay (Ankara) araması: ${controller.all.length} otopark · ${controller.counts} · anlık doluluklu: ${controller.all.where((p) => p.hasLiveOccupancy).length}',
    );
    _shell.open(Dest.list);
    await _wait(3);
    await _shot('ankara_liste');

    await _offline();

    _log('Toplam süre: ${DateTime.now().difference(started).inSeconds} sn · başarısız denetim: $_fails');
    _shell.open(Dest.home);
    if (config.directory != null) {
      await File('${config.directory}${Platform.pathSeparator}selftest.txt').writeAsString(_report.toString());
      exit(0);
    } else {
      debugPrint('PARKSENSE_CAPTURE done');
    }
  }

  void _openDetail(Parking p) {
    if (AppPlatform.isDesktop) {
      _shell.open(Dest.map);
      _shell.openParking(p);
    } else {
      _shell.open(Dest.home);
      _shell.openParkingDetailRoute(p);
    }
  }

  Future<void> _wait(int s) => Future<void>.delayed(Duration(seconds: s));

  Future<void> _check(String name, Future<String> Function() body) async {
    final sw = Stopwatch()..start();
    try {
      final detail = await body();
      _log('OK   $name (${sw.elapsedMilliseconds} ms): $detail');
    } catch (e) {
      _fails++;
      final f = AppFailure.from(e);
      _log('FAIL $name (${sw.elapsedMilliseconds} ms): ${f.kind} ${f.source ?? ''} ${f.detail ?? ''}');
    }
  }

  String _short(Object? o, [int n = 400]) {
    final s = jsonEncode(o);
    return s.length > n ? '${s.substring(0, n)}…' : s;
  }

  Future<void> _probeSources() async {
    final repo = controller.repo;
    _log('--- Veri kaynakları (gerçek istekler) ---');
    await _check('İSPARK /Park ham yanıt', () async {
      final json = await Http.getJson(Uri.parse('${repo.ispark.baseUrl}/Park'), source: 'İSPARK');
      final list = json as List;
      return '${list.length} kayıt · alanlar: ${(list.first as Map).keys.join(',')} · örnek: ${_short(list.first, 300)}';
    });
    String? sampleId;
    await _check('İSPARK ayrıştırma', () async {
      final all = await repo.ispark.fetchAll(force: true);
      final live = all.where((p) => p.occupancy != null).length;
      sampleId = all.firstWhere((p) => p.occupancy != null, orElse: () => all.first).id.split(':').last;
      final types = <ParkingType, int>{};
      for (final p in all) {
        types[p.type] = (types[p.type] ?? 0) + 1;
      }
      return '${all.length} otopark · anlık doluluklu $live · türler $types';
    });
    if (sampleId != null) {
      await _check('İSPARK /ParkDetay ham yanıt', () async {
        final json = await Http.getJson(Uri.parse('${repo.ispark.baseUrl}/ParkDetay?id=$sampleId'), source: 'İSPARK');
        final obj = json is List ? json.first : json;
        return 'alanlar: ${(obj as Map).keys.join(',')} · tariff: ${_short(obj['tariff'], 300)} · updateDate: ${obj['updateDate']} · monthlyFee: ${obj['monthlyFee']}';
      });
    }
    await _check('Overpass (Taksim 1,5 km)', () async {
      final r = await repo.osm.fetch(SearchArea(taksim.point, 1500));
      final named = r.items.where((p) => !p.nameIsGenerated).length;
      final priced = r.items.where((p) => p.price?.hasAny == true).length;
      return '${r.items.length} otopark · adlı $named · fiyat/ücret etiketli $priced · OSM veri zamanı ${r.dataTime}';
    });
    await _check('Overpass yedek sunucu', () async {
      final backup = OsmProvider(endpoints: [repo.osm.endpoints.last]);
      final r = await backup.fetch(SearchArea(kizilay.point, 1000));
      return '${repo.osm.endpoints.last} → ${r.items.length} otopark';
    });
    await _check('Nominatim adres arama ("Kadıköy")', () async {
      final r = await controller.geocoding.search('Kadıköy');
      return '${r.length} sonuç · ilk: ${r.first.name} / ${r.first.detail} ${r.first.point}';
    });
    await _check('CARTO harita döşemesi', () async {
      final code = await Http.status('https://a.basemaps.cartocdn.com/rastertiles/voyager/15/19151/12302.png');
      if (code != 200) throw AppFailure(FailureKind.server, detail: 'HTTP $code');
      return 'HTTP $code';
    });
    await _check('OpenStreetMap harita döşemesi', () async {
      final code = await Http.status('https://tile.openstreetmap.org/15/19151/12302.png');
      if (code != 200) throw AppFailure(FailureKind.server, detail: 'HTTP $code');
      return 'HTTP $code';
    });
    await _check('Google Maps yol tarifi bağlantısı', () async {
      final web = NavigationService.webUri(taksim.point).toString();
      final app = NavigationService.appUri(taksim.point).toString();
      final code = await Http.status(web);
      return 'web: $web (HTTP $code) · uygulama: $app';
    });
    final u = await const UpdateService().check(controller.updateEndpoint);
    _log('INFO Güncelleme denetimi: ${u.state.name} ${u.latest ?? ''} ${u.message ?? ''}');
  }

  Future<void> _dbChecks() async {
    final db = controller.db;
    _log('--- SQLite ---');
    await _check('Şema ve yabancı anahtarlar', () async {
      if (!db.foreignKeysOn) throw const AppFailure(FailureKind.unknown, detail: 'foreign_keys kapalı');
      return 'user_version ${db.userVersion} · ${db.parkingCount} kayıt · kaynaklar ${db.dataSourceRows().length}';
    });
    await _check('Upsert favorileri korur', () async {
      final favs = db.favoriteIds();
      if (favs.isEmpty) throw const AppFailure(FailureKind.unknown, detail: 'favori yok');
      final again = favs.map(db.parking).whereType<Parking>().toList();
      db.upsertParkings(again);
      final after = db.favoriteIds();
      if (after.length != favs.length) throw AppFailure(FailureKind.unknown, detail: '${favs.length} → ${after.length}');
      return '${after.length} favori yeniden yazımdan sonra korundu';
    });
    await _check('Yerel kayıt kaskad silme', () async {
      final p = db.parking('local:selftest')!;
      controller.toggleFavorite(p);
      controller.recordVisit(p);
      final deps = db.dependentsOf(p.id);
      controller.deleteLocal(p.id);
      final left = db.dependentsOf(p.id);
      if (db.parking(p.id) != null || left.favorites + left.visits != 0) throw const AppFailure(FailureKind.unknown, detail: 'silinmedi');
      return 'önce fav=${deps.favorites} ziyaret=${deps.visits} · sonra 0';
    });
  }

  Future<void> _offline() async {
    _log('--- Bağlantı yok senaryosu (gerçek bağlantı hatası: kapalı port) ---');
    final repo = controller.repo;
    final ispark = repo.ispark.baseUrl;
    final osm = repo.osm.endpoints;
    repo.ispark.baseUrl = 'https://127.0.0.1:9/ispark';
    repo.osm.endpoints = ['https://127.0.0.1:9/api/interpreter'];
    repo.clearMemoryCaches();
    await controller.selectPlace(taksim);
    final noLive = controller.all.every((p) => !p.hasLiveOccupancy);
    final ok = controller.fromCache && noLive;
    if (!ok) _fails++;
    _log(
      '${ok ? 'OK  ' : 'FAIL'} Çevrimdışı: önbellekten ${controller.all.length} otopark · doluluk gösterilmiyor=$noLive · uyarı=${controller.warnings.length}',
    );
    _shell.open(Dest.list);
    await _wait(2);
    await _shot('cevrimdisi_onbellek');
    await controller.selectPlace(const PlaceResult(name: 'Van', detail: 'İpekyolu', point: GeoPoint(38.5012, 43.3729)));
    final ok2 = controller.phase == LoadPhase.error && controller.all.isEmpty;
    if (!ok2) _fails++;
    _log('${ok2 ? 'OK  ' : 'FAIL'} Çevrimdışı + önbellek yok: hata durumu "${controller.failure?.message}"');
    await _wait(2);
    await _shot('baglanti_yok');
    repo.ispark.baseUrl = ispark;
    repo.osm.endpoints = osm;
    repo.clearMemoryCaches();
  }

  Future<void> _shot(String name) async {
    _step++;
    final id = '${_step.toString().padLeft(2, '0')}_$name';
    if (config.directory == null) {
      debugPrint('PARKSENSE_CAPTURE step=$id');
      await Future<void>.delayed(const Duration(milliseconds: 3500));
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await File('${config.directory}${Platform.pathSeparator}$id.png').writeAsBytes(bytes!.buffer.asUint8List());
    _log('EKRAN $id kaydedildi');
  }
}
