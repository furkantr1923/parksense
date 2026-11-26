import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../domain/filters.dart';
import '../../domain/parking.dart';
import '../../state/app_controller.dart';
import 'common.dart';
import 'filter_panel.dart';
import 'parking_card.dart';

/// Durum başlığı: yükleniyor, çevrimdışı, kaynak uyarıları.
class StatusBanners extends StatelessWidget {
  const StatusBanners({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final items = <Widget>[
      if (c.fromCache)
        NoticeBanner(
          text: 'Çevrimdışı: sunuculara ulaşılamadı, cihazdaki önbellek gösteriliyor. Doluluk bilgisi gösterilmez.',
          icon: Icons.cloud_off_rounded,
          color: AppColors.busy,
          action: TextButton(onPressed: () => c.load(force: true), child: const Text('Yenile')),
        )
      else
        for (final w in c.warnings) NoticeBanner(text: w, icon: Icons.warning_amber_rounded, color: AppColors.busy),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [for (final w in items) Padding(padding: const EdgeInsets.only(bottom: 8), child: w)],
    );
  }
}

/// Filtre özeti + sayfalı otopark listesi.
class ResultsList extends StatefulWidget {
  const ResultsList({
    super.key,
    required this.onOpen,
    this.selectedId,
    this.header,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
  });

  final ValueChanged<Parking> onOpen;
  final String? selectedId;
  final Widget? header;
  final EdgeInsets padding;

  @override
  State<ResultsList> createState() => _ResultsListState();
}

class _ResultsListState extends State<ResultsList> {
  static const pageSize = 30;
  int _shown = pageSize;
  List<Parking>? _last;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final items = c.visible;
    if (!identical(items, _last)) {
      _last = items;
      _shown = pageSize; // Yeni sonuçlarda sayfalama başa döner.
    }
    final count = items.length < _shown ? items.length : _shown;
    final more = items.length > _shown;

    Widget body;
    if (c.center == null) {
      body = const EmptyState(
        icon: Icons.travel_explore_rounded,
        title: 'Aramaya başlayın',
        message: 'Konumunuzu kullanın ya da şehir/adres arayın.',
      );
    } else if (c.phase == LoadPhase.loading && c.all.isEmpty) {
      body = const Center(
        child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
      );
    } else if (c.phase == LoadPhase.error) {
      body = EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Otoparklar yüklenemedi',
        message: c.failure?.message,
        action: FilledButton(onPressed: () => c.load(force: true), child: const Text('Tekrar dene')),
      );
    } else if (c.all.isEmpty) {
      body = const EmptyState(
        icon: Icons.local_parking_rounded,
        title: 'Bu bölgede otopark bulunamadı',
        message:
            'Veri kaynaklarında bu çevre için kayıt yok. Arama yarıçapını Ayarlar\'dan büyütebilir veya başka bir yer arayabilirsiniz.',
      );
    } else if (items.isEmpty) {
      body = EmptyState(
        icon: Icons.filter_alt_off_rounded,
        title: 'Filtrelere uyan otopark yok',
        message: '${c.all.length} otopark bulundu ancak hiçbiri seçili filtrelere uymuyor.',
        action: OutlinedButton(onPressed: () => c.setFilter(c.filter.reset()), child: const Text('Filtreleri temizle')),
      );
    } else {
      body = const SizedBox.shrink();
    }

    final showList = body is SizedBox;
    return ListView.builder(
      padding: widget.padding,
      itemCount: 2 + (showList ? count + (more ? 1 : 0) : 1),
      itemBuilder: (ctx, i) {
        if (i == 0) return widget.header ?? const SizedBox.shrink();
        if (i == 1) return _SummaryBar(count: items.length, total: c.all.length);
        if (!showList) return body;
        final j = i - 2;
        if (j == count) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: OutlinedButton(
              onPressed: () => setState(() => _shown += pageSize),
              child: Text('Daha fazla göster (${items.length - _shown} kaldı)'),
            ),
          );
        }
        final p = items[j];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ParkingCard(parking: p, selected: p.id == widget.selectedId, onTap: () => widget.onOpen(p)),
        );
      },
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.count, required this.total});

  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final n = c.filter.activeCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatusBanners(),
          Row(
            children: [
              Expanded(
                child: Text(
                  c.center == null
                      ? ''
                      : c.phase == LoadPhase.loading
                      ? 'Yükleniyor…'
                      : (count == total ? '$total otopark' : '$count / $total otopark'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (c.phase == LoadPhase.loading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              PopupMenuButton(
                tooltip: 'Sırala',
                initialValue: c.filter.sort,
                onSelected: (s) => c.setFilter(c.filter.copyWith(sort: s)),
                itemBuilder: (_) => [for (final s in ParkingSort.values) PopupMenuItem(value: s, child: Text(s.label))],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sort_rounded, size: 18, color: AppColors.muted),
                      const SizedBox(width: 4),
                      Text(c.filter.sort.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              Badge(
                isLabelVisible: n > 0,
                label: Text('$n'),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 12)),
                  onPressed: () => FilterPanel.show(context),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Filtre'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
