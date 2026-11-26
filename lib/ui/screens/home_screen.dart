import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/providers/geocoding.dart';
import '../../domain/parking.dart';
import '../../services/location_service.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/parking_card.dart';
import '../widgets/results_list.dart';
import 'search_screen.dart';

/// Açılış ekranı (Android): logo, arama, konum izni, yakındakiler, öne çıkanlar.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenMap, required this.onOpen});

  final VoidCallback onOpenMap;
  final ValueChanged<Parking> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final (featured, featuredWhy) = c.featured;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => c.load(force: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const BrandLogo(size: 40, subtitle: 'Akıllı otopark keşif sistemi'),
            const SizedBox(height: 18),
            _SearchField(onTap: () => SearchScreen.open(context, onParking: onOpen)),
            const SizedBox(height: 14),
            if (!c.centerIsUser) _LocationCard(status: c.locationStatus),
            if (c.center != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.place_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      c.centerLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(onPressed: onOpenMap, icon: const Icon(Icons.map_outlined, size: 18), label: const Text('Haritada aç')),
                ],
              ),
              const StatusBanners(),
              const SizedBox(height: 6),
              if (c.phase == LoadPhase.loading && c.all.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (c.phase == LoadPhase.error)
                NoticeBanner(
                  text: c.failure?.message ?? 'Veriler yüklenemedi.',
                  icon: Icons.cloud_off_rounded,
                  color: AppColors.full,
                  action: TextButton(onPressed: () => c.load(force: true), child: const Text('Tekrar dene')),
                )
              else if (c.all.isEmpty)
                const NoticeBanner(text: 'Bu çevrede veri kaynaklarında kayıtlı otopark bulunamadı.', icon: Icons.search_off_rounded)
              else ...[
                SectionTitle('Yakındaki otoparklar', subtitle: '${c.all.length} otopark bulundu'),
                SizedBox(
                  height: 170,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: c.nearby.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => ParkingTile(parking: c.nearby[i], onTap: () => onOpen(c.nearby[i])),
                  ),
                ),
                const SizedBox(height: 22),
                if (featured.isNotEmpty) ...[
                  SectionTitle('Öne çıkanlar', subtitle: featuredWhy),
                  for (final p in featured)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ParkingCard(parking: p, onTap: () => onOpen(p)),
                    ),
                ],
              ],
            ] else ...[
              const SizedBox(height: 22),
              const SectionTitle('Şehir seçin', subtitle: 'Konum izni vermeden de arama yapabilirsiniz'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final city in GeocodingService.cities)
                    ActionChip(
                      avatar: const Icon(Icons.location_city_rounded, size: 18),
                      label: Text(city.name),
                      onPressed: () => c.selectPlace(city),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            const NoticeBanner(
              text:
                  'Kapsam: Türkiye geneli OpenStreetMap verisi ve İstanbul İSPARK resmî verisi. Tüm otoparklar kapsanmayabilir; anlık doluluk yalnızca resmî kaynağı olan otoparklarda gösterilir.',
              icon: Icons.info_outline_rounded,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: const Row(
            children: [
              Icon(Icons.search_rounded, color: AppColors.muted),
              SizedBox(width: 10),
              Expanded(
                child: Text('Şehir, ilçe, adres veya otopark ara', style: TextStyle(color: AppColors.muted, fontSize: 15)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.status});

  final LocationStatus status;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final denied = status == LocationStatus.deniedForever;
    return Card(
      color: AppColors.primary.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.my_location_rounded, color: AppColors.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Yakınınızdaki otoparkları görün', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              status.message.isNotEmpty
                  ? status.message
                  : 'Konumunuz yalnızca yakındaki otoparkları bulmak için kullanılır ve hiçbir yere kaydedilmez.',
              style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.35),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: c.locating ? null : () => denied ? c.location.openSettings() : c.useMyLocation(),
                  icon: c.locating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.near_me_rounded, size: 18),
                  label: Text(denied ? 'Ayarları aç' : 'Konumumu kullan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
