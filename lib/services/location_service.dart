import 'package:geolocator/geolocator.dart';

import '../core/geo.dart';

enum LocationStatus {
  unknown,
  granted,
  denied,
  deniedForever,
  serviceDisabled,
  error;

  String get message => switch (this) {
    LocationStatus.unknown => '',
    LocationStatus.granted => '',
    LocationStatus.denied => 'Konum izni verilmedi. Şehir veya adres arayarak devam edebilirsiniz.',
    LocationStatus.deniedForever =>
      'Konum izni kalıcı olarak reddedildi. İsterseniz cihaz ayarlarından izin verebilir ya da şehir/adres arayabilirsiniz.',
    LocationStatus.serviceDisabled => 'Konum servisi kapalı. Açın ya da şehir/adres arayın.',
    LocationStatus.error => 'Konum alınamadı. Şehir veya adres arayarak devam edebilirsiniz.',
  };
}

class LocationResult {
  const LocationResult(this.status, [this.point]);

  final LocationStatus status;
  final GeoPoint? point;
}

/// Konum yalnızca kullanıcı "Konumumu kullan" dediğinde istenir ve
/// hiçbir yere kaydedilmez (yalnızca bellekte tutulur).
class LocationService {
  Future<LocationResult> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(LocationStatus.serviceDisabled);
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return const LocationResult(LocationStatus.denied);
      if (perm == LocationPermission.deniedForever) return const LocationResult(LocationStatus.deniedForever);
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
        );
        return LocationResult(LocationStatus.granted, GeoPoint(pos.latitude, pos.longitude));
      } catch (_) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return LocationResult(LocationStatus.granted, GeoPoint(last.latitude, last.longitude));
        return const LocationResult(LocationStatus.error);
      }
    } catch (_) {
      return const LocationResult(LocationStatus.error);
    }
  }

  /// İzin daha önce verilmişse konumu döndürür; izin penceresi AÇMAZ.
  Future<LocationResult> currentIfGranted() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) {
        return LocationResult(perm == LocationPermission.deniedForever ? LocationStatus.deniedForever : LocationStatus.unknown);
      }
      return await current();
    } catch (_) {
      return const LocationResult(LocationStatus.unknown);
    }
  }

  Future<bool> openSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }
}
