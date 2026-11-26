import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../domain/parking.dart';
import 'common.dart';

/// Liste satırı: ad, tür, mesafe, fiyat, doluluk, kaynak.
class ParkingCard extends StatelessWidget {
  const ParkingCard({super.key, required this.parking, required this.onTap, this.selected = false, this.trailing});

  final Parking parking;
  final VoidCallback onTap;
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final p = parking;
    final d = c.distanceTo(p);
    final fav = c.isFavorite(p);
    final color = p.isLocal ? AppColors.local : AppColors.occupancy(p.hasLiveOccupancy ? p.occupancy!.ratio : null);
    final meta = [p.type.shortLabel, if (p.district != null) p.district!, if (d != null) Fmt.distance(d)].join(' · ');
    return Card(
      color: selected ? AppColors.primary.withValues(alpha: 0.05) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? AppColors.primary : AppColors.line, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(typeIcon(p.type), color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: p.nameIsGenerated ? AppColors.muted : AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            priceSummary(p),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: p.price?.hasAny == true ? AppColors.ink : AppColors.muted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SourceBadge(p.source, compact: true),
                        if (p.isOpenNow == false) ...[const SizedBox(width: 6), const Pill('Kapalı', color: AppColors.full)],
                      ],
                    ),
                    const SizedBox(height: 6),
                    OccupancyView(p, dense: true),
                  ],
                ),
              ),
              trailing ??
                  IconButton(
                    tooltip: fav ? 'Favorilerden çıkar' : 'Favorilere ekle',
                    onPressed: () => AppScope.read(context).toggleFavorite(p),
                    icon: Icon(
                      fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: fav ? AppColors.full : AppColors.muted,
                      size: 22,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ana sayfadaki yatay kart.
class ParkingTile extends StatelessWidget {
  const ParkingTile({super.key, required this.parking, required this.onTap});

  final Parking parking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final p = parking;
    final d = c.distanceTo(p);
    final color = p.isLocal ? AppColors.local : AppColors.occupancy(p.hasLiveOccupancy ? p.occupancy!.ratio : null);
    return SizedBox(
      width: 236,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(typeIcon(p.type), size: 20, color: color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        p.type.shortLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (d != null) Text(Fmt.distance(d), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.2),
                ),
                const Spacer(),
                Text(
                  priceSummary(p),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                OccupancyView(p, dense: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
