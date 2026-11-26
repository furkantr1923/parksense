import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'capture/capture_runner.dart';
import 'data/db/app_database.dart';
import 'data/parking_repository.dart';
import 'state/app_controller.dart';
import 'ui/shell.dart';

/// PARKSENSE giriş noktası.
///
/// `--capture=<klasör>` (Windows) veya `--dart-define=PARKSENSE_CAPTURE=true`
/// (Android) ile başlatılırsa uygulama kendi kendini gerçek verilerle sınar,
/// ekran görüntüleri alır ve rapor yazar (CI). Normal kullanımda çalışmaz.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Düşük bellekli cihazlar için çözülmüş görüntü önbelleğini sınırla.
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 64 << 20
    ..maximumSize = 300;
  await initializeDateFormatting('tr_TR');

  final capture = CaptureConfig.fromArgs(args);
  final db = capture != null ? AppDatabase.inMemory() : await _openDatabase();
  final controller = AppController(
    db: db,
    repo: ParkingRepository(db: db),
  )..init();
  final shellKey = GlobalKey<AppShellState>();
  final boundaryKey = capture != null ? GlobalKey() : null;

  runApp(ParkSenseApp(controller: controller, shellKey: shellKey, boundaryKey: boundaryKey));

  if (capture != null) {
    await CaptureRunner(config: capture, controller: controller, shellKey: shellKey, boundaryKey: boundaryKey!).run();
  } else {
    // İzin daha önce verildiyse konumu sessizce kullan; izin penceresi açmaz.
    await controller.tryAutoLocate();
  }
}

Future<AppDatabase> _openDatabase() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final path = '${dir.path}${Platform.pathSeparator}parksense.db';
  try {
    return AppDatabase.open(path);
  } catch (e) {
    // Bozuk veritabanı: silmek yerine yedeğe taşı, yenisini oluştur (veri kaybı yok).
    final f = File(path);
    if (await f.exists()) {
      await f.rename('$path.bozuk-${DateTime.now().millisecondsSinceEpoch}');
    }
    return AppDatabase.open(path);
  }
}
