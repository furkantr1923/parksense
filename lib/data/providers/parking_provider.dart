import '../../core/geo.dart';
import '../../domain/data_source.dart';
import '../../domain/parking.dart';

/// Aranacak bölge: merkez + yarıçap.
class SearchArea {
  const SearchArea(this.center, this.radiusM);

  final GeoPoint center;
  final double radiusM;

  /// Önbellek anahtarı: ~110 m'ye yuvarlanmış merkez + yarıçap.
  String get key => '${center.lat.toStringAsFixed(3)},${center.lng.toStringAsFixed(3)},${radiusM.round()}';
}

class ProviderResult {
  const ProviderResult(this.items, {this.dataTime});

  final List<Parking> items;

  /// Kaynağın veri zamanı (ör. OSM veritabanı anlık görüntüsü).
  final DateTime? dataTime;
}

/// Her veri sağlayıcısı bağımsız bir modüldür; yeni bir belediye API'si
/// eklemek için bu arayüzü uygulamak ve [ParkingRepository]'ye eklemek yeterlidir.
abstract class ParkingProvider {
  DataSourceInfo get info;

  /// Bu sağlayıcı bölgeyi kapsıyor mu? (Gereksiz istekleri önler.)
  bool covers(SearchArea area);

  Future<ProviderResult> fetch(SearchArea area);
}
