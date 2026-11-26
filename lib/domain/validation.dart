import '../core/format.dart';
import '../core/geo.dart';

/// Yönetim ekranı form doğrulaması. Saf fonksiyonlar → birim testleriyle sınanır.
class Validators {
  Validators._();

  static String? name(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Otopark adı zorunludur.';
    if (s.length < 3) return 'Ad en az 3 karakter olmalı.';
    if (s.length > 120) return 'Ad en fazla 120 karakter olabilir.';
    return null;
  }

  static String? latitude(String? v) {
    final d = Fmt.parseNumber(v);
    if (d == null) return 'Geçerli bir enlem girin (ör. 41.0369).';
    if (d < -90 || d > 90) return 'Enlem -90 ile 90 arasında olmalı.';
    return null;
  }

  static String? longitude(String? v) {
    final d = Fmt.parseNumber(v);
    if (d == null) return 'Geçerli bir boylam girin (ör. 28.9850).';
    if (d < -180 || d > 180) return 'Boylam -180 ile 180 arasında olmalı.';
    return null;
  }

  /// Uygulama kapsamı Türkiye'dir.
  static String? inTurkey(double lat, double lng) =>
      Geo.turkeyBounds.contains(GeoPoint(lat, lng)) ? null : 'Koordinat Türkiye sınırları dışında görünüyor.';

  static String? optionalPrice(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final d = Fmt.parseNumber(v);
    if (d == null) return 'Geçerli bir tutar girin.';
    if (d < 0) return 'Tutar negatif olamaz.';
    if (d > 1000000) return 'Tutar çok yüksek.';
    return null;
  }

  static String? optionalCapacity(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = int.tryParse(v.trim());
    if (n == null) return 'Kapasite tam sayı olmalı.';
    if (n < 0) return 'Kapasite negatif olamaz.';
    if (n > 100000) return 'Kapasite çok yüksek.';
    return null;
  }

  static String? optionalPhone(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final digits = v.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length < 7 || digits.length > 15) return 'Geçerli bir telefon numarası girin.';
    if (!RegExp(r'^[\d\s()+\-]+$').hasMatch(v.trim())) return 'Telefon yalnızca rakam, boşluk, +, -, ( ) içerebilir.';
    return null;
  }

  static String? optionalUrl(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final u = Uri.tryParse(v.trim());
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty || !u.host.contains('.')) {
      return 'Adres http:// veya https:// ile başlamalı.';
    }
    return null;
  }

  static String? sourceNote(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Veri kaynağını belirtin (ör. "İşletme beyanı", "Yerinde gözlem").';
    if (s.length > 200) return 'En fazla 200 karakter.';
    return null;
  }
}
