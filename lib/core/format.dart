import 'package:intl/intl.dart';

/// Türkçe biçimlendirme yardımcıları (₺, mesafe, tarih).
class Fmt {
  Fmt._();

  static final _tl = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
  static final _tlRound = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);
  static final _int = NumberFormat.decimalPattern('tr_TR');

  /// 45 → "₺45", 42,5 → "₺42,50".
  static String tl(double amount) => amount == amount.roundToDouble() ? _tlRound.format(amount) : _tl.format(amount);

  static String integer(int v) => _int.format(v);

  static String distance(double meters) {
    if (meters < 1000) return '${(meters / 10).round() * 10} m';
    final km = meters / 1000;
    return '${km.toStringAsFixed(km < 10 ? 1 : 0).replaceAll('.', ',')} km';
  }

  static String percent(double ratio) => '%${(ratio * 100).round()}';

  static String dateTime(DateTime t) => DateFormat('d MMMM y HH:mm', 'tr_TR').format(t.toLocal());

  static String date(DateTime t) => DateFormat('d MMMM y', 'tr_TR').format(t.toLocal());

  /// "3 dk önce", "2 saat önce", aksi hâlde tarih.
  static String relative(DateTime t, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final d = n.difference(t);
    if (d.isNegative || d.inSeconds < 60) return 'az önce';
    if (d.inMinutes < 60) return '${d.inMinutes} dk önce';
    if (d.inHours < 24) return '${d.inHours} saat önce';
    if (d.inDays < 7) return '${d.inDays} gün önce';
    return date(t);
  }

  /// Türkçe ve İngilizce biçimli sayıları ayrıştırır: "1.250,50", "1250.5", "45".
  static double? parseNumber(String? raw) {
    if (raw == null) return null;
    var s = raw.trim().replaceAll(RegExp(r'[^\d.,-]'), '');
    if (s.isEmpty) return null;
    if (s.contains(',') && s.contains('.')) {
      // Son ayraç ondalık ayracıdır.
      if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        s = s.replaceAll(',', '');
      }
    } else if (s.contains(',')) {
      s = s.replaceAll(',', '.');
    } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s)) {
      s = s.replaceAll('.', ''); // "1.250" → binlik ayracı
    }
    return double.tryParse(s);
  }

  /// Türkçe karakterleri ASCII büyük harfe indirger (eşleştirme için).
  static String fold(String s) {
    const map = {
      'ı': 'I',
      'i': 'I',
      'İ': 'I',
      'ş': 'S',
      'Ş': 'S',
      'ğ': 'G',
      'Ğ': 'G',
      'ü': 'U',
      'Ü': 'U',
      'ö': 'O',
      'Ö': 'O',
      'ç': 'C',
      'Ç': 'C',
      'â': 'A',
      'Â': 'A',
      'î': 'I',
      'û': 'U',
    };
    final b = StringBuffer();
    for (final ch in s.split('')) {
      b.write(map[ch] ?? ch.toUpperCase());
    }
    return b.toString();
  }
}
