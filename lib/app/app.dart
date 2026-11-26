import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../state/app_controller.dart';
import '../ui/shell.dart';
import 'app_scope.dart';
import 'theme.dart';

class ParkSenseApp extends StatelessWidget {
  const ParkSenseApp({super.key, required this.controller, required this.shellKey, this.boundaryKey});

  final AppController controller;
  final GlobalKey<AppShellState> shellKey;

  /// Öz-sınama modunda ekran görüntüsü almak için kök sınır.
  final GlobalKey? boundaryKey;

  @override
  Widget build(BuildContext context) {
    final app = AppScope(
      controller: controller,
      child: MaterialApp(
        title: 'PARKSENSE',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: AppShell(key: shellKey),
      ),
    );
    return boundaryKey == null ? app : RepaintBoundary(key: boundaryKey, child: app);
  }
}
