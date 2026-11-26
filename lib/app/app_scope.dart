import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../state/app_controller.dart';

/// Denetleyiciyi ağaca taşır; değiştiğinde dinleyen widget'lar yeniden çizilir.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child}) : super(notifier: controller);

  static AppController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Dinlemeden erişim (olay işleyicileri için).
  static AppController read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

/// Platform farkları: Android tam sürüm, Windows sade masaüstü sürümü.
class AppPlatform {
  AppPlatform._();

  static bool? debugDesktopOverride;

  static bool get isDesktop => debugDesktopOverride ?? (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS));

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
}
