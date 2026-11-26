import '../core/geo.dart';
import 'parking.dart';

/// Haritadaki işaret kümesi: tek otopark ya da yakın otoparkların grubu.
class MarkerCluster {
  MarkerCluster(this.center, this.items);

  final GeoPoint center;
  final List<Parking> items;

  bool get isSingle => items.length == 1;
}

/// Ekran ızgarası tabanlı kümeleme. Binlerce işareti tek tek çizmek yerine
/// yakınlaştırmaya göre gruplar; düşük donanımda akıcılığı korur.
class Clusterer {
  Clusterer._();

  /// [cellPx]: bir küme hücresinin ekran pikseli cinsinden kenarı.
  /// [disableAtZoom] ve üstünde kümeleme yapılmaz.
  static List<MarkerCluster> cluster(List<Parking> items, double zoom, {double cellPx = 64, double disableAtZoom = 16.5}) {
    if (zoom >= disableAtZoom || items.length < 2) {
      return [
        for (final p in items) MarkerCluster(p.location, [p]),
      ];
    }
    final z = zoom.floorToDouble();
    final cells = <(int, int), List<Parking>>{};
    for (final p in items) {
      final (x, y) = Geo.project(p.location, z);
      final key = ((x / cellPx).floor(), (y / cellPx).floor());
      (cells[key] ??= []).add(p);
    }
    return [
      for (final group in cells.values)
        MarkerCluster(
          GeoPoint(
            group.map((p) => p.location.lat).reduce((a, b) => a + b) / group.length,
            group.map((p) => p.location.lng).reduce((a, b) => a + b) / group.length,
          ),
          group,
        ),
    ];
  }
}
