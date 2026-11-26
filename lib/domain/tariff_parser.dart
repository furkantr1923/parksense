import '../core/format.dart';
import 'parking.dart';

/// Kaynakların serbest metin tarifelerini yapılandırılmış fiyata çevirir.
///
/// Ayrıştırılamayan kısımlar atılmaz: özgün metin [PriceInfo.rawText]
/// olarak saklanır ve kullanıcıya aynen gösterilir. Hiçbir fiyat tahmin
/// edilmez.
class TariffParser {
  TariffParser._();

  static final _tierRe = RegExp(r'^\s*(.+?)\s*[:=]\s*(\d[\d.,]*)\s*(?:TL|TRY|₺)?\s*$', caseSensitive: false);

  /// İSPARK "tariff" alanı. Örnek biçim: "0-1 Saat : 45 TL;1-2 Saat : 55 TL;…".
  static PriceInfo? ispark({String? tariff, double? monthlyFee, int? freeMinutes, DateTime? updatedAt}) {
    final tiers = <PriceTier>[];
    final unparsed = <String>[];
    if (tariff != null && tariff.trim().isNotEmpty) {
      for (final part in tariff.split(RegExp(r'[;\n|]'))) {
        final p = part.trim();
        if (p.isEmpty) continue;
        final m = _tierRe.firstMatch(p);
        final amount = m == null ? null : Fmt.parseNumber(m.group(2));
        if (m != null && amount != null) {
          tiers.add(PriceTier(_cleanLabel(m.group(1)!), amount));
        } else {
          unparsed.add(p);
        }
      }
    }
    double? hourly;
    double? daily;
    for (final t in tiers) {
      final l = Fmt.fold(t.label);
      if (hourly == null && RegExp(r'^0\s*-\s*1\s*SAAT|^1\s*SAAT|^ILK\s*1?\s*SAAT|SAATLIK').hasMatch(l)) hourly = t.amount;
      if (daily == null && RegExp(r'GUNLUK|0\s*-\s*24|^24\s*SAAT|TAM\s*GUN').hasMatch(l)) daily = t.amount;
    }
    final monthly = (monthlyFee != null && monthlyFee > 0) ? monthlyFee : null;
    final info = PriceInfo(
      hourly: hourly,
      daily: daily,
      monthly: monthly,
      tiers: tiers,
      freeMinutes: (freeMinutes != null && freeMinutes > 0) ? freeMinutes : null,
      rawText: unparsed.isEmpty ? null : unparsed.join('; '),
      sourceId: 'ispark',
      updatedAt: updatedAt,
    );
    return info.hasAny ? info : null;
  }

  static String _cleanLabel(String s) => s.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'\s*-\s*'), '-').trim();

  static final _osmChargeRe = RegExp(
    r'(\d[\d.,]*)\s*(?:TRY|TL|₺)\s*(?:/|per\s+)\s*(hour|hr|h|saat|day|d|gün|gun|month|ay)\b',
    caseSensitive: false,
  );

  /// OpenStreetMap `fee` ve `charge` etiketleri.
  /// Örnekler: fee=no → ücretsiz; charge="20 TRY/hour" → saatlik ₺20.
  static PriceInfo? osm({String? fee, String? charge, DateTime? updatedAt}) {
    bool? isFree;
    final f = fee?.trim().toLowerCase();
    if (f == 'no' || f == 'free') isFree = true;
    if (f == 'yes') isFree = false;
    double? hourly;
    double? daily;
    double? monthly;
    String? raw;
    if (charge != null && charge.trim().isNotEmpty) {
      var matched = false;
      for (final m in _osmChargeRe.allMatches(charge)) {
        final amount = Fmt.parseNumber(m.group(1));
        if (amount == null) continue;
        matched = true;
        final unit = Fmt.fold(m.group(2)!);
        if (unit.startsWith('H') || unit == 'SAAT') {
          hourly ??= amount;
        } else if (unit.startsWith('D') || unit.startsWith('GUN')) {
          daily ??= amount;
        } else {
          monthly ??= amount;
        }
      }
      if (!matched) raw = charge.trim();
      if (matched && isFree == null) isFree = false;
    }
    final info = PriceInfo(
      hourly: hourly,
      daily: daily,
      monthly: monthly,
      isFree: isFree,
      rawText: raw,
      sourceId: 'osm',
      updatedAt: updatedAt,
    );
    return info.hasAny ? info : null;
  }
}
