import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../domain/data_source.dart';
import '../../domain/parking.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 36, this.showText = true, this.subtitle});

  final double size;
  final bool showText;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.23),
          child: Image.asset('assets/brand/logo.png', width: size, height: size, filterQuality: FilterQuality.medium),
        ),
        if (showText) ...[
          SizedBox(width: size * 0.3),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'PARK',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * 0.52, color: AppColors.ink, letterSpacing: 0.5),
                      ),
                      TextSpan(
                        text: 'SENSE',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * 0.52, color: AppColors.primary, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: size * 0.3, color: AppColors.muted, fontWeight: FontWeight.w500),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Küçük, renkli etiket.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = AppColors.muted, this.icon, this.filled = false});

  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: filled ? color : color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: filled ? Colors.white : color), const SizedBox(width: 4)],
          Text(
            text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: filled ? Colors.white : color),
          ),
        ],
      ),
    );
  }
}

class SourceBadge extends StatelessWidget {
  const SourceBadge(this.source, {super.key, this.compact = false});

  final DataSourceInfo source;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (source.reliability) {
      Reliability.official => (AppColors.free, Icons.verified_outlined),
      Reliability.community => (AppColors.muted, Icons.groups_outlined),
      Reliability.userEntered => (AppColors.local, Icons.edit_location_alt_outlined),
    };
    final label = compact
        ? switch (source.id) {
            'ispark' => 'İSPARK',
            'osm' => 'OSM',
            _ => 'Yerel',
          }
        : source.reliability.label;
    return Tooltip(
      message: '${source.name}\n${source.reliability.label}',
      child: Pill(label, color: color, icon: icon),
    );
  }
}

/// Doluluk göstergesi. Anlık veri yoksa bunu açıkça yazar.
class OccupancyView extends StatelessWidget {
  const OccupancyView(this.parking, {super.key, this.dense = false});

  final Parking parking;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final o = parking.hasLiveOccupancy ? parking.occupancy : null;
    if (o == null) {
      return Text(
        'Anlık doluluk bilgisi mevcut değil',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: dense ? 12 : 13, color: AppColors.muted),
      );
    }
    final r = o.ratio;
    final color = AppColors.occupancy(r);
    final text = o.isFull ? 'Dolu' : '${Fmt.integer(o.free)} boş yer';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.circle, size: 9, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: text,
                      style: TextStyle(fontSize: dense ? 12.5 : 14, fontWeight: FontWeight.w700, color: color),
                    ),
                    TextSpan(
                      text: '  / ${Fmt.integer(o.capacity)}',
                      style: TextStyle(fontSize: dense ? 12 : 13, color: AppColors.muted),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (r != null) ...[
              const SizedBox(width: 8),
              Text(
                '${Fmt.percent(r)} dolu',
                style: TextStyle(fontSize: dense ? 12 : 13, color: AppColors.muted, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
        if (!dense) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: r ?? 0, minHeight: 8, color: color, backgroundColor: AppColors.line),
          ),
        ],
      ],
    );
  }
}

String priceSummary(Parking p) {
  final pr = p.price;
  if (pr == null) return 'Fiyat bilgisi yok';
  if (pr.isFree == true) return 'Ücretsiz';
  if (pr.hourly != null) return '${Fmt.tl(pr.hourly!)} / saat';
  if (pr.tiers.isNotEmpty) return '${Fmt.tl(pr.tiers.first.amount)} (${pr.tiers.first.label})';
  if (pr.daily != null) return '${Fmt.tl(pr.daily!)} / gün';
  if (pr.monthly != null) return '${Fmt.tl(pr.monthly!)} / ay';
  if (pr.isFree == false) return 'Ücretli (tutar bilinmiyor)';
  if (pr.freeMinutes != null) return 'İlk ${pr.freeMinutes} dk ücretsiz';
  return 'Fiyat bilgisi yok';
}

class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.text, this.icon = Icons.info_outline, this.color = AppColors.primary, this.action});

  final String text;
  final IconData icon;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35))),
          ?action,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(icon, size: 30, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, height: 1.4),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class StarRating extends StatelessWidget {
  const StarRating({super.key, required this.value, this.onChanged, this.size = 30});

  final int value;
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Semantics(
            button: onChanged != null,
            label: '$i yıldız',
            child: InkResponse(
              radius: size * 0.7,
              onTap: onChanged == null ? null : () => onChanged!(value == i ? 0 : i),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: size,
                  color: i <= value ? const Color(0xFFF59E0B) : AppColors.unknown,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

IconData typeIcon(ParkingType t) => switch (t) {
  ParkingType.open => Icons.local_parking_rounded,
  ParkingType.indoor => Icons.garage_outlined,
  ParkingType.underground => Icons.subway_outlined,
  ParkingType.multiStorey => Icons.apartment_rounded,
  ParkingType.street => Icons.add_road_rounded,
  ParkingType.unknown => Icons.local_parking_outlined,
};
