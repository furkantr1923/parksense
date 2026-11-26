import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/providers/geocoding.dart';
import '../../domain/parking.dart';
import '../../services/location_service.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/parking_map.dart';
import '../widgets/results_list.dart';
import 'detail_screen.dart';
import 'search_screen.dart';

/// Windows ana ekranı: geniş ekran için liste | harita | detay paneli.
class DesktopExplore extends StatelessWidget {
  const DesktopExplore({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final listWidth = width >= 1400 ? 420.0 : 360.0;
    return ValueListenableBuilder<Parking?>(
      valueListenable: c.selected,
      builder: (context, sel, _) {
        final selected = sel == null ? null : c.live(sel);
        return Row(
          children: [
            SizedBox(
              width: listWidth,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const BrandLogo(size: 34, subtitle: 'Akıllı otopark keşif sistemi'),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, backgroundColor: Colors.white),
                                onPressed: () => SearchScreen.open(context, onParking: (p) => c.selected.value = p),
                                icon: const Icon(Icons.search_rounded, color: AppColors.muted),
                                label: Text(
                                  c.center == null ? 'Şehir, adres veya otopark ara' : c.centerLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: 'Konumumu kullan',
                              onPressed: c.locating
                                  ? null
                                  : () async {
                                      final s = await c.useMyLocation();
                                      if (context.mounted && s != LocationStatus.granted) {
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.message)));
                                      }
                                    },
                              icon: const Icon(Icons.my_location_rounded),
                            ),
                            IconButton(
                              tooltip: 'Yenile',
                              onPressed: c.center == null ? null : () => c.load(force: true),
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ),
                        if (c.center == null) ...[
                          const SizedBox(height: 14),
                          const Text('Hızlı başlangıç', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final city in GeocodingService.cities)
                                ActionChip(label: Text(city.name), onPressed: () => c.selectPlace(city)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: ResultsList(
                      selectedId: selected?.id,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      onOpen: (p) {
                        c.selected.value = p;
                        c.cameraRequest.value = (p.location, 17);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Stack(
                children: [
                  ParkingMap(items: c.visible, selectedId: selected?.id, onSelect: (p) => c.selected.value = p),
                  if (c.phase == LoadPhase.loading)
                    const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 3)),
                ],
              ),
            ),
            if (selected != null) ...[
              const VerticalDivider(width: 1),
              SizedBox(
                width: width >= 1400 ? 440 : 380,
                child: ColoredBox(
                  color: AppColors.background,
                  child: DetailView(key: ValueKey(selected.id), parking: selected, onClose: () => c.selected.value = null),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
