/// Veri kaynağının güvenilirlik düzeyi. Kullanıcıya her kayıtta gösterilir.
enum Reliability {
  /// Resmî kurum / işletme API'si (ör. İBB Açık Veri — İSPARK).
  official,

  /// Topluluk tarafından girilen açık veri (ör. OpenStreetMap).
  community,

  /// Kullanıcının bu cihazda elle girdiği, doğrulanmamış kayıt.
  userEntered;

  String get label => switch (this) {
    Reliability.official => 'Resmî kaynak',
    Reliability.community => 'Topluluk verisi',
    Reliability.userEntered => 'Yerel kayıt (doğrulanmamış)',
  };

  String get explanation => switch (this) {
    Reliability.official => 'Bilgiler otoparkı işleten kurumun yayımladığı açık veri servisinden alınır.',
    Reliability.community =>
      'Bilgiler OpenStreetMap gönüllüleri tarafından girilmiştir; eksik veya güncel olmayabilir. Fiyat ve çalışma saatlerini yerinde teyit edin.',
    Reliability.userEntered => 'Bu kayıt bu cihazdaki yönetim ekranından elle eklenmiştir ve doğrulanmamıştır. Diğer cihazlara aktarılmaz.',
  };
}

/// Bir veri sağlayıcısının tanımı (DataSource tablosunda da tutulur).
class DataSourceInfo {
  const DataSourceInfo({
    required this.id,
    required this.name,
    required this.url,
    required this.license,
    required this.reliability,
    required this.realtimeOccupancy,
    required this.description,
  });

  final String id;
  final String name;
  final String url;
  final String license;
  final Reliability reliability;
  final bool realtimeOccupancy;
  final String description;
}

/// Uygulamanın kullandığı tüm veri kaynakları — gerçek, erişilebilir ve
/// kullanım koşulları incelenmiş servisler (bkz. docs/DATA_SOURCES.md).
class DataSources {
  DataSources._();

  static const ispark = DataSourceInfo(
    id: 'ispark',
    name: 'İBB Açık Veri — İSPARK',
    url: 'https://data.ibb.gov.tr',
    license: 'İBB Açık Veri Lisansı',
    reliability: Reliability.official,
    realtimeOccupancy: true,
    description: 'İstanbul\'daki İSPARK otoparklarının konum, kapasite, anlık boş yer, çalışma saati ve tarife bilgileri.',
  );

  static const osm = DataSourceInfo(
    id: 'osm',
    name: 'OpenStreetMap (Overpass API)',
    url: 'https://www.openstreetmap.org/copyright',
    license: 'ODbL 1.0 — © OpenStreetMap katkıda bulunanlar',
    reliability: Reliability.community,
    realtimeOccupancy: false,
    description: 'Türkiye genelinde amenity=parking olarak işaretlenmiş otoparklar. Anlık doluluk bilgisi içermez.',
  );

  static const local = DataSourceInfo(
    id: 'local',
    name: 'Yerel yönetim kaydı',
    url: '',
    license: 'Kullanıcı verisi (yalnızca bu cihaz)',
    reliability: Reliability.userEntered,
    realtimeOccupancy: false,
    description: 'Yönetim ekranından bu cihazda eklenen otoparklar. Başka cihazlarla eşitlenmez.',
  );

  static const all = [ispark, osm, local];

  static DataSourceInfo byId(String id) => all.firstWhere((s) => s.id == id, orElse: () => local);
}
