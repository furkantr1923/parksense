import '../core/geo.dart';
import 'parking.dart';

enum OccupancyFilter {
  any,
  liveOnly,
  hasSpace,
  lowOccupancy;

  String get label => switch (this) {
    OccupancyFilter.any => 'Tümü',
    OccupancyFilter.liveOnly => 'Anlık verisi olanlar',
    OccupancyFilter.hasSpace => 'Boş yeri olanlar',
    OccupancyFilter.lowOccupancy => 'Doluluğu %70\'in altında',
  };
}

enum ParkingSort {
  distance,
  price,
  freeSpaces,
  name;

  String get label => switch (this) {
    ParkingSort.distance => 'Mesafe',
    ParkingSort.price => 'Saatlik fiyat',
    ParkingSort.freeSpaces => 'Boş yer',
    ParkingSort.name => 'Ad',
  };
}

/// Birlikte çalışan filtreler. Boş/null alan = o ölçüt uygulanmaz.
class ParkingFilter {
  const ParkingFilter({
    this.types = const {},
    this.maxDistanceM,
    this.maxHourlyPrice,
    this.includeUnknownPrice = false,
    this.onlyFree = false,
    this.occupancy = OccupancyFilter.any,
    this.query = '',
    this.sort = ParkingSort.distance,
  });

  final Set<ParkingType> types;
  final double? maxDistanceM;
  final double? maxHourlyPrice;

  /// Fiyat filtresi açıkken fiyatı bilinmeyenler de listelensin mi?
  final bool includeUnknownPrice;
  final bool onlyFree;
  final OccupancyFilter occupancy;
  final String query;
  final ParkingSort sort;

  static const none = ParkingFilter();

  int get activeCount =>
      (types.isNotEmpty ? 1 : 0) +
      (maxDistanceM != null ? 1 : 0) +
      ((maxHourlyPrice != null || onlyFree) ? 1 : 0) +
      (occupancy != OccupancyFilter.any ? 1 : 0);

  bool get isActive => activeCount > 0 || query.trim().isNotEmpty;

  ParkingFilter copyWith({
    Set<ParkingType>? types,
    double? maxDistanceM,
    bool clearDistance = false,
    double? maxHourlyPrice,
    bool clearPrice = false,
    bool? includeUnknownPrice,
    bool? onlyFree,
    OccupancyFilter? occupancy,
    String? query,
    ParkingSort? sort,
  }) => ParkingFilter(
    types: types ?? this.types,
    maxDistanceM: clearDistance ? null : (maxDistanceM ?? this.maxDistanceM),
    maxHourlyPrice: clearPrice ? null : (maxHourlyPrice ?? this.maxHourlyPrice),
    includeUnknownPrice: includeUnknownPrice ?? this.includeUnknownPrice,
    onlyFree: onlyFree ?? this.onlyFree,
    occupancy: occupancy ?? this.occupancy,
    query: query ?? this.query,
    sort: sort ?? this.sort,
  );

  ParkingFilter reset() => ParkingFilter(sort: sort);

  bool matches(Parking p, {GeoPoint? origin}) {
    if (types.isNotEmpty && !types.contains(p.type)) return false;
    if (maxDistanceM != null && origin != null && Geo.distanceM(origin, p.location) > maxDistanceM!) return false;
    if (onlyFree && p.price?.isFree != true) return false;
    if (maxHourlyPrice != null) {
      final h = p.price?.effectiveHourly;
      if (h == null) {
        if (!includeUnknownPrice) return false;
      } else if (h > maxHourlyPrice!) {
        return false;
      }
    }
    switch (occupancy) {
      case OccupancyFilter.any:
        break;
      case OccupancyFilter.liveOnly:
        if (!p.hasLiveOccupancy) return false;
      case OccupancyFilter.hasSpace:
        if (!p.hasLiveOccupancy || p.occupancy!.isFull) return false;
      case OccupancyFilter.lowOccupancy:
        final r = p.hasLiveOccupancy ? p.occupancy!.ratio : null;
        if (r == null || r >= 0.70) return false;
    }
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final hay = '${p.name} ${p.address ?? ''} ${p.district ?? ''} ${p.city ?? ''}'.toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }

  /// Filtreleri uygular ve sıralar. [origin] varsa mesafe hesaplanır.
  List<Parking> apply(Iterable<Parking> items, {GeoPoint? origin}) {
    final list = items.where((p) => matches(p, origin: origin)).toList();
    final dist = <String, double>{
      if (origin != null)
        for (final p in list) p.id: Geo.distanceM(origin, p.location),
    };
    int byDistance(Parking a, Parking b) => (dist[a.id] ?? 0).compareTo(dist[b.id] ?? 0);
    switch (sort) {
      case ParkingSort.distance:
        list.sort(byDistance);
      case ParkingSort.price:
        // Fiyatı bilinmeyenler sona.
        list.sort((a, b) {
          final x = a.price?.effectiveHourly, y = b.price?.effectiveHourly;
          if (x == null && y == null) return byDistance(a, b);
          if (x == null) return 1;
          if (y == null) return -1;
          final c = x.compareTo(y);
          return c != 0 ? c : byDistance(a, b);
        });
      case ParkingSort.freeSpaces:
        list.sort((a, b) {
          final x = a.hasLiveOccupancy ? a.occupancy!.free : -1;
          final y = b.hasLiveOccupancy ? b.occupancy!.free : -1;
          final c = y.compareTo(x);
          return c != 0 ? c : byDistance(a, b);
        });
      case ParkingSort.name:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }
}
