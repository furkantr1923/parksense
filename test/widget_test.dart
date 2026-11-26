import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:parksense/app/app.dart';
import 'package:parksense/app/app_scope.dart';
import 'package:parksense/core/geo.dart';
import 'package:parksense/data/db/app_database.dart';
import 'package:parksense/data/parking_repository.dart';
import 'package:parksense/domain/filters.dart';
import 'package:parksense/domain/parking.dart';
import 'package:parksense/services/location_service.dart';
import 'package:parksense/state/app_controller.dart';
import 'package:parksense/ui/screens/detail_screen.dart';
import 'package:parksense/ui/shell.dart';
import 'package:parksense/ui/widgets/parking_map.dart';

import 'data_test.dart' show FakeIspark, FakeOsm;

class DeniedLocation extends LocationService {
  @override
  Future<LocationResult> current() async => const LocationResult(LocationStatus.denied);

  @override
  Future<LocationResult> currentIfGranted() async => const LocationResult(LocationStatus.unknown);
}

AppController makeController() {
  final db = AppDatabase.inMemory();
  return AppController(
    db: db,
    repo: ParkingRepository(db: db, ispark: FakeIspark(), osm: FakeOsm()),
    location: DeniedLocation(),
  )..init();
}

Future<void> pumpApp(WidgetTester t, AppController c, {required bool desktop, Size size = const Size(412, 915)}) async {
  AppPlatform.debugDesktopOverride = desktop;
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ParkSenseApp(controller: c, shellKey: GlobalKey<AppShellState>()));
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    MapConfig.tilesEnabled = false;
  });

  testWidgets('Android açılış: logo, arama, konum izni kartı ve şehir seçimi', (t) async {
    final c = makeController();
    await pumpApp(t, c, desktop: false);
    expect(find.text('Akıllı otopark keşif sistemi'), findsOneWidget);
    expect(find.text('Şehir, ilçe, adres veya otopark ara'), findsOneWidget);
    expect(find.text('Konumumu kullan'), findsOneWidget);
    expect(find.text('Ana sayfa'), findsOneWidget);

    // Konum izni reddedilince açıklayıcı mesaj ve manuel arama
    await t.tap(find.text('Konumumu kullan'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Konum izni verilmedi'), findsOneWidget);

    await t.tap(find.widgetWithText(ActionChip, 'İstanbul'));
    await t.pump(const Duration(milliseconds: 500));
    expect(c.all.length, 5);
    expect(find.text('Yakındaki otoparklar'), findsOneWidget);
    expect(find.text('Öne çıkanlar'), findsOneWidget);
  });

  testWidgets('Harita ↔ liste geçişi ve filtre sonucu yok mesajı', (t) async {
    final c = makeController();
    await pumpApp(t, c, desktop: false);
    await c.setCenter(const GeoPoint(41.0369, 28.9850), 'Taksim');
    await t.pump(const Duration(milliseconds: 300));
    t.state<AppShellState>(find.byType(AppShell)).open(Dest.list);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('5 otopark'), findsOneWidget);

    c.setFilter(const ParkingFilter(types: {ParkingType.underground}));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Filtrelere uyan otopark yok'), findsOneWidget);
    await t.tap(find.text('Filtreleri temizle'));
    await t.pump(const Duration(milliseconds: 300));
    expect(c.visible.length, 5);

    await t.tap(find.text('Harita'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(ParkingMap), findsOneWidget);
  });

  testWidgets('Detay: eksik bilgiler "Bilgi mevcut değil", doluluk yoksa açık uyarı', (t) async {
    final c = makeController();
    await pumpApp(t, c, desktop: false);
    const p = Parking(id: 'osm:node/9', sourceId: 'osm', name: 'Deneme Otoparkı', location: GeoPoint(41.0, 29.0));
    await t.pumpWidget(
      AppScope(
        controller: c,
        child: const MaterialApp(home: DetailScreen(parking: p)),
      ),
    );
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Deneme Otoparkı'), findsOneWidget);
    expect(find.text('Anlık doluluk bilgisi mevcut değil'), findsOneWidget);
    expect(find.text('Fiyat bilgisi mevcut değil'), findsOneWidget);
    expect(find.text('Bilgi mevcut değil'), findsWidgets);
    expect(find.text('Topluluk verisi'), findsOneWidget);

    await t.tap(find.text('Favori'));
    await t.pump();
    expect(c.isFavorite(p), isTrue);
    expect(c.db.recent().single.$1.id, p.id, reason: 'son görüntülenenlere eklendi');
  });

  testWidgets('Windows: yan menü, Yönetim uyarısı ve Hakkında ekranında geliştirici', (t) async {
    final c = makeController();
    await pumpApp(t, c, desktop: true, size: const Size(1366, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Hızlı başlangıç'), findsOneWidget);

    await t.tap(find.text('Yönetim'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('diğer cihazlara otomatik olarak aktarılmaz'), findsOneWidget);

    await t.tap(find.text('Hakkında'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Furkan'), findsOneWidget);
    expect(find.text('Geliştirici'), findsOneWidget);
  });
}
