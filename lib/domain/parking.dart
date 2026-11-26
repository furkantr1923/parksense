import '../core/geo.dart';
import 'data_source.dart';

enum ParkingType {
  open,
  indoor,
  underground,
  multiStorey,
  street,
  unknown;

  String get label => switch (this) {
    ParkingType.open => 'Açık otopark',
    ParkingType.indoor => 'Kapalı otopark',
    ParkingType.underground => 'Yer altı otoparkı',
    ParkingType.multiStorey => 'Katlı otopark',
    ParkingType.street => 'Yol kenarı',
    ParkingType.unknown => 'Türü belirtilmemiş',
  };

  String get shortLabel => switch (this) {
    ParkingType.open => 'Açık',
    ParkingType.indoor => 'Kapalı',
    ParkingType.underground => 'Yer altı',
    ParkingType.multiStorey => 'Katlı',
    ParkingType.street => 'Yol kenarı',
    ParkingType.unknown => 'Belirsiz',
  };

  static ParkingType parse(String? s) => ParkingType.values.firstWhere((t) => t.name == s, orElse: () => ParkingType.unknown);
}

/// Doğrulanmış bir kaynaktan gelen doluluk bilgisi. Bu nesne yalnızca
/// sensör/işletme API'si gibi gerçek bir kaynak varsa oluşturulur.
class Occupancy {
  const Occupancy({required this.capacity, required this.free, required this.observedAt, this.observedAtIsFetchTime = false});

  final int capacity;
  final int free;

  /// Kaynağın bildirdiği güncelleme zamanı; kaynak bildirmiyorsa verinin alındığı an.
  final DateTime observedAt;
  final bool observedAtIsFetchTime;

  int get occupied => (capacity - free).clamp(0, capacity);

  /// 0..1 arası doluluk oranı; kapasite 0 ise null.
  double? get ratio => capacity > 0 ? occupied / capacity : null;

  bool get isFull => free <= 0;

  Map<String, Object?> toJson() => {'capacity': capacity, 'free': free, 'at': observedAt.toIso8601String(), 'fetch': observedAtIsFetchTime};
}

/// Tarife satırı: "0-1 Saat — ₺45" gibi.
class PriceTier {
  const PriceTier(this.label, this.amount);

  final String label;
  final double amount;

  @override
  bool operator ==(Object other) => other is PriceTier && other.label == label && other.amount == amount;

  @override
  int get hashCode => Object.hash(label, amount);

  @override
  String toString() => '$label=$amount';
}

/// Fiyat bilgisi. Her alan yalnızca kaynakta gerçekten varsa doludur;
/// eksik fiyatlar asla tahmin edilmez.
class PriceInfo {
  const PriceInfo({
    this.hourly,
    this.daily,
    this.monthly,
    this.tiers = const [],
    this.freeMinutes,
    this.isFree,
    this.rawText,
    required this.sourceId,
    this.updatedAt,
  });

  final double? hourly;
  final double? daily;
  final double? monthly;
  final List<PriceTier> tiers;
  final int? freeMinutes;

  /// Kaynak "ücretsiz" diyorsa true, "ücretli" diyorsa false, bilinmiyorsa null.
  final bool? isFree;

  /// Ayrıştırılamayan özgün tarife metni (kaynağın kendi ifadesi).
  final String? rawText;
  final String sourceId;
  final DateTime? updatedAt;

  bool get hasAnyAmount => hourly != null || daily != null || monthly != null || tiers.isNotEmpty;

  bool get hasAny => hasAnyAmount || isFree != null || freeMinutes != null || (rawText?.isNotEmpty ?? false);

  /// Filtre ve sıralamada kullanılan saatlik bedel (ücretsizse 0).
  double? get effectiveHourly => isFree == true ? 0 : hourly;

  PriceInfo copyWith({double? hourly, double? daily, double? monthly, DateTime? updatedAt}) => PriceInfo(
    hourly: hourly ?? this.hourly,
    daily: daily ?? this.daily,
    monthly: monthly ?? this.monthly,
    tiers: tiers,
    freeMinutes: freeMinutes,
    isFree: isFree,
    rawText: rawText,
    sourceId: sourceId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class Parking {
  const Parking({
    required this.id,
    required this.sourceId,
    required this.name,
    required this.location,
    this.address,
    this.city,
    this.district,
    this.type = ParkingType.unknown,
    this.isOpenNow,
    this.openingHours,
    this.capacity,
    this.occupancy,
    this.price,
    this.phone,
    this.website,
    this.photos = const [],
    this.accessibility,
    this.amenities = const [],
    this.operatorName,
    this.accessNote,
    this.sourceRef,
    this.updatedAt,
    this.fetchedAt,
    this.nameIsGenerated = false,
  });

  /// Kaynağa göre önekli kimlik: "ispark:123", "osm:way/456", "local:…".
  final String id;
  final String sourceId;
  final String name;
  final bool nameIsGenerated;
  final GeoPoint location;
  final String? address;
  final String? city;
  final String? district;
  final ParkingType type;

  /// Kaynak açık/kapalı bilgisini veriyorsa dolu, aksi hâlde null.
  final bool? isOpenNow;
  final String? openingHours;
  final int? capacity;
  final Occupancy? occupancy;
  final PriceInfo? price;
  final String? phone;
  final String? website;
  final List<String> photos;
  final String? accessibility;
  final List<String> amenities;
  final String? operatorName;
  final String? accessNote;

  /// Kaynaktaki özgün kayıt bağlantısı (ör. OSM nesne sayfası).
  final String? sourceRef;

  /// Kaynağın bildirdiği son güncelleme.
  final DateTime? updatedAt;

  /// Verinin uygulama tarafından alındığı an.
  final DateTime? fetchedAt;

  DataSourceInfo get source => DataSources.byId(sourceId);

  bool get isLocal => sourceId == DataSources.local.id;

  bool get hasLiveOccupancy => occupancy != null && source.realtimeOccupancy;

  /// Toplam kapasite: anlık veriden ya da statik kayıttan.
  int? get totalCapacity => occupancy?.capacity ?? capacity;

  Parking copyWith({
    Occupancy? occupancy,
    bool clearOccupancy = false,
    PriceInfo? price,
    String? address,
    String? district,
    DateTime? updatedAt,
    DateTime? fetchedAt,
  }) => Parking(
    id: id,
    sourceId: sourceId,
    name: name,
    nameIsGenerated: nameIsGenerated,
    location: location,
    address: address ?? this.address,
    city: city,
    district: district ?? this.district,
    type: type,
    isOpenNow: isOpenNow,
    openingHours: openingHours,
    capacity: capacity,
    occupancy: clearOccupancy ? null : (occupancy ?? this.occupancy),
    price: price ?? this.price,
    phone: phone,
    website: website,
    photos: photos,
    accessibility: accessibility,
    amenities: amenities,
    operatorName: operatorName,
    accessNote: accessNote,
    sourceRef: sourceRef,
    updatedAt: updatedAt ?? this.updatedAt,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );

  @override
  String toString() => 'Parking($id, $name)';
}
