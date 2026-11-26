/// Uygulama kimliği ve sürüm bilgileri (tek kaynak).
class AppInfo {
  AppInfo._();

  static const name = 'PARKSENSE';
  static const version = '1.0.0';
  static const developer = 'Furkan';
  static const packageName = 'com.furkan.parksense';
  static const repoUrl = 'https://github.com/furkantr1923/parksense';
  static const issuesUrl = '$repoUrl/issues';

  /// Güncelleme denetimi için varsayılan uç nokta: GitHub Releases.
  /// Ayarlar ekranından değiştirilebilir veya boş bırakılarak kapatılabilir.
  static const defaultUpdateEndpoint = 'https://api.github.com/repos/furkantr1923/parksense/releases/latest';

  /// Açık veri servislerinin kullanım politikaları uygulamanın kendini
  /// tanıtmasını ister (Nominatim, Overpass, OSM döşemeleri).
  static const userAgent = 'PARKSENSE/$version (+$repoUrl)';

  static const tagline = 'Akıllı otopark keşif sistemi';
}
