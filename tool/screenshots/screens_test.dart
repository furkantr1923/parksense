// Arayüz önizleme görüntüleri (sunum/README için). Test verisiyle çalışır,
// ağa çıkmaz. Çalıştırma: flutter test tool/screenshots --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:parksense/app/app.dart';
import 'package:parksense/app/app_scope.dart';
import 'package:parksense/core/geo.dart';
import 'package:parksense/data/db/app_database.dart';
import 'package:parksense/data/parking_repository.dart';
import 'package:parksense/domain/filters.dart';
import 'package:parksense/domain/parking.dart';
import 'package:parksense/state/app_controller.dart';
import 'package:parksense/ui/shell.dart';
import 'package:parksense/ui/widgets/parking_map.dart';

import '../../test/data_test.dart' show FakeIspark, FakeOsm;
import '../../test/widget_test.dart' show DeniedLocation;

Future<void> loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    MapConfig.tilesEnabled = false;
    await loadFont('DMSans', ['Regular', 'Medium', 'SemiBold', 'Bold'].map((w) => 'assets/fonts/DMSans-$w.ttf').toList());
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/sdk/flutter';
    await loadFont('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  });

  Future<(AppController, GlobalKey<AppShellState>)> boot(WidgetTester t, {required bool desktop, required Size logical}) async {
    AppPlatform.debugDesktopOverride = desktop;
    t.view.physicalSize = logical * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final db = AppDatabase.inMemory();
    final c = AppController(db: db, repo: ParkingRepository(db: db, ispark: FakeIspark(), osm: FakeOsm()), location: DeniedLocation())..init();
    final key = GlobalKey<AppShellState>();
    await t.pumpWidget(ParkSenseApp(controller: c, shellKey: key));
    await t.pump(const Duration(milliseconds: 300));
    return (c, key);
  }

  Future<void> shot(WidgetTester t, String name) async {
    await t.pump(const Duration(milliseconds: 600));
    await expectLater(find.byType(ParkSenseApp), matchesGoldenFile('out/$name.png'));
  }

  testWidgets('android', (t) async {
    final (c, k) = await boot(t, desktop: false, logical: const Size(412, 892));
    await shot(t, 'android_01_acilis');
    await t.runAsync(() => c.setCenter(const GeoPoint(41.0369, 28.9850), 'Taksim, Beyoğlu'));
    await shot(t, 'android_02_ana_sayfa');
    k.currentState!.open(Dest.list);
    await shot(t, 'android_03_liste');
    k.currentState!.open(Dest.map);
    await shot(t, 'android_04_harita');
    final p = c.all.firstWhere((x) => x.id == 'ispark:1001');
    k.currentState!.open(Dest.home);
    await t.pump();
    k.currentState!.openParkingDetailRoute(p);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await shot(t, 'android_05_detay_ispark');
    await t.drag(find.byType(ListView).last, const Offset(0, -700));
    await shot(t, 'android_06_detay_fiyat');
    k.currentState!.open(Dest.list);
    c.setFilter(const ParkingFilter(types: {ParkingType.underground}));
    await shot(t, 'android_07_filtre_sonuc_yok');
    c.setFilter(ParkingFilter.none);
    k.currentState!.open(Dest.manage);
    await t.pump(const Duration(milliseconds: 400));
    await shot(t, 'android_08_yonetim');
  });

  testWidgets('windows', (t) async {
    final (c, k) = await boot(t, desktop: true, logical: const Size(1440, 860));
    await t.runAsync(() => c.setCenter(const GeoPoint(41.0369, 28.9850), 'Taksim, Beyoğlu'));
    c.selected.value = c.all.firstWhere((x) => x.id == 'ispark:1001');
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(milliseconds: 300));
    await shot(t, 'windows_01_kesfet');
    k.currentState!.open(Dest.about);
    await shot(t, 'windows_02_hakkinda');
  });
}
