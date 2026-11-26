import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../core/geo.dart';

enum NavResult { openedApp, openedBrowser, failed }

/// Google Maps yol tarifi bağlantıları.
///
/// Android: önce Google Maps uygulamasının navigasyon şeması
/// (`google.navigation:`) denenir; uygulama yoksa tarayıcıda açılan
/// evrensel Maps URL'si kullanılır. Windows: doğrudan tarayıcı.
class NavigationService {
  const NavigationService();

  static Uri appUri(GeoPoint p) => Uri.parse('google.navigation:q=${p.lat.toStringAsFixed(6)},${p.lng.toStringAsFixed(6)}&mode=d');

  /// Google'ın belgelenmiş "Maps URLs" biçimi — her platformda çalışır.
  static Uri webUri(GeoPoint p, {String? name}) => Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '${p.lat.toStringAsFixed(6)},${p.lng.toStringAsFixed(6)}',
    'travelmode': 'driving',
  });

  static Uri searchUri(GeoPoint p) =>
      Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '${p.lat.toStringAsFixed(6)},${p.lng.toStringAsFixed(6)}'});

  Future<NavResult> navigate(GeoPoint p) async {
    if (Platform.isAndroid) {
      try {
        if (await launchUrl(appUri(p), mode: LaunchMode.externalNonBrowserApplication)) return NavResult.openedApp;
      } catch (_) {
        // Google Maps yüklü değil → tarayıcı.
      }
    }
    try {
      if (await launchUrl(webUri(p), mode: LaunchMode.externalApplication)) return NavResult.openedBrowser;
    } catch (_) {}
    return NavResult.failed;
  }

  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static Uri? phoneUri(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    return digits.length < 7 ? null : Uri(scheme: 'tel', path: digits);
  }

  static Uri? websiteUri(String site) {
    var s = site.trim();
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'https://$s';
    final u = Uri.tryParse(s);
    return (u == null || u.host.isEmpty) ? null : u;
  }
}
