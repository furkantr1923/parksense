import 'dart:math' as math;

/// Coğrafi yardımcılar: mesafe, sınır kutusu ve Web Mercator izdüşümü.
///
/// Harita paketinden bağımsız tutulur; böylece birim testlerinde
/// yalnızca saf Dart ile doğrulanabilir.
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  bool get isValid => lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;

  @override
  bool operator ==(Object other) => other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => '(${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)})';
}

class Geo {
  Geo._();

  static const double earthRadiusM = 6371008.8;

  /// İki nokta arasındaki büyük daire mesafesi (Haversine), metre.
  static double distanceM(GeoPoint a, GeoPoint b) {
    final dLat = _rad(b.lat - a.lat);
    final dLng = _rad(b.lng - a.lng);
    final h = math.pow(math.sin(dLat / 2), 2) + math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
  }

  static double _rad(double d) => d * math.pi / 180;

  /// Türkiye'nin kaba sınır kutusu (veri doğrulama için).
  static const turkeyBounds = GeoBounds(south: 35.80, west: 25.60, north: 42.15, east: 44.85);

  /// İSPARK'ın hizmet verdiği İstanbul il sınırlarını kapsayan kutu.
  static const istanbulBounds = GeoBounds(south: 40.80, west: 27.95, north: 41.60, east: 29.95);

  /// Web Mercator piksel koordinatı (256 px döşeme, verilen yakınlaştırma).
  static (double x, double y) project(GeoPoint p, double zoom) {
    final scale = 256 * math.pow(2, zoom).toDouble();
    final x = (p.lng + 180) / 360 * scale;
    final s = math.sin(_rad(p.lat.clamp(-85.05112878, 85.05112878)));
    final y = (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * scale;
    return (x, y);
  }
}

class GeoBounds {
  const GeoBounds({required this.south, required this.west, required this.north, required this.east});

  final double south;
  final double west;
  final double north;
  final double east;

  bool contains(GeoPoint p) => p.lat >= south && p.lat <= north && p.lng >= west && p.lng <= east;

  /// Merkez etrafında yarıçapı kapsayan kutu ile kesişiyor mu?
  bool intersectsCircle(GeoPoint center, double radiusM) {
    final dLat = radiusM / 111320.0;
    final dLng = radiusM / (111320.0 * math.cos(center.lat * math.pi / 180).abs().clamp(0.01, 1.0));
    return !(center.lat + dLat < south || center.lat - dLat > north || center.lng + dLng < west || center.lng - dLng > east);
  }
}
