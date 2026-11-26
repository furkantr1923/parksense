import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../domain/parking.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/filter_panel.dart';
import '../widgets/parking_card.dart';
import '../widgets/parking_map.dart';
import '../widgets/results_list.dart';
import 'search_screen.dart';

/// Android keşif ekranı: harita ↔ liste geçişi, filtre ve seçim kartı.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key, required this.onOpen});

  final ValueChanged<Parking> onOpen;

  static final showList = ValueNotifier<bool>(false);

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  Parking? _selected;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: ExploreScreen.showList,
      builder: (context, listMode, _) {
        final sel = _selected == null ? null : c.live(_selected!);
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _TopBar(listMode: listMode, onOpen: widget.onOpen),
                Expanded(
                  child: listMode
                      ? ResultsList(onOpen: widget.onOpen)
                      : Stack(
                          children: [
                            ParkingMap(
                              items: c.visible,
                              selectedId: sel?.id,
                              onSelect: (p) => setState(() => _selected = p),
                              bottomPadding: sel == null ? 0 : 170,
                            ),
                            if (c.phase == LoadPhase.loading)
                              const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 3)),
                            if (c.center == null)
                              const Positioned(
                                left: 16,
                                right: 16,
                                top: 16,
                                child: NoticeBanner(
                                  text: 'Konumunuzu kullanın veya yukarıdan şehir/adres arayın.',
                                  icon: Icons.travel_explore_rounded,
                                ),
                              ),
                            if (c.center != null && c.phase == LoadPhase.ready && c.visible.isEmpty)
                              Positioned(
                                left: 16,
                                right: 16,
                                top: 16,
                                child: NoticeBanner(
                                  text: c.all.isEmpty ? 'Bu bölgede otopark bulunamadı.' : 'Filtrelere uyan otopark yok.',
                                  icon: Icons.search_off_rounded,
                                  color: AppColors.busy,
                                  action: c.all.isEmpty
                                      ? null
                                      : TextButton(onPressed: () => c.setFilter(c.filter.reset()), child: const Text('Temizle')),
                                ),
                              ),
                            if (c.fromCache || c.phase == LoadPhase.error)
                              Positioned(
                                left: 16,
                                right: 16,
                                bottom: sel == null ? 16 : 186,
                                child: NoticeBanner(
                                  text: c.phase == LoadPhase.error
                                      ? (c.failure?.message ?? 'Veri yüklenemedi.')
                                      : 'Çevrimdışı: önbellekteki otoparklar gösteriliyor.',
                                  icon: Icons.cloud_off_rounded,
                                  color: AppColors.busy,
                                  action: TextButton(onPressed: () => c.load(force: true), child: const Text('Yenile')),
                                ),
                              ),
                            if (sel != null)
                              Positioned(
                                left: 12,
                                right: 12,
                                bottom: 12,
                                child: Material(
                                  elevation: 6,
                                  borderRadius: BorderRadius.circular(16),
                                  child: ParkingCard(
                                    parking: sel,
                                    onTap: () => widget.onOpen(sel),
                                    trailing: IconButton(
                                      tooltip: 'Kapat',
                                      onPressed: () => setState(() => _selected = null),
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.listMode, required this.onOpen});

  final bool listMode;
  final ValueChanged<Parking> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final n = c.filter.activeCount;
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => SearchScreen.open(context, onParking: onOpen),
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded, color: AppColors.muted, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              c.center == null ? 'Şehir, adres veya otopark ara' : c.centerLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: c.center == null ? AppColors.muted : AppColors.ink, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Badge(
                isLabelVisible: n > 0,
                label: Text('$n'),
                child: IconButton.filledTonal(
                  tooltip: 'Filtreler',
                  onPressed: () => FilterPanel.show(context),
                  icon: const Icon(Icons.tune_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.map_outlined, size: 18), label: Text('Harita')),
              ButtonSegment(value: true, icon: Icon(Icons.view_list_rounded, size: 18), label: Text('Liste')),
            ],
            selected: {listMode},
            onSelectionChanged: (s) => ExploreScreen.showList.value = s.first,
          ),
        ],
      ),
    );
  }
}
