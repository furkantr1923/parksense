import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../domain/filters.dart';
import '../../domain/parking.dart';

/// Fiyat, mesafe, doluluk ve tür filtreleri + sıralama. Filtreler birlikte
/// çalışır; alttaki düğme uygulanınca kaç sonuç kalacağını önceden gösterir.
class FilterPanel extends StatefulWidget {
  const FilterPanel({super.key, required this.onDone, this.scrollController});

  final VoidCallback onDone;
  final ScrollController? scrollController;

  static Future<void> show(BuildContext context) {
    if (AppPlatform.isDesktop || MediaQuery.sizeOf(context).width >= 840) {
      return showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
            child: FilterPanel(onDone: () => Navigator.pop(ctx)),
          ),
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        maxChildSize: 0.95,
        builder: (ctx, sc) => FilterPanel(onDone: () => Navigator.pop(ctx), scrollController: sc),
      ),
    );
  }

  @override
  State<FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<FilterPanel> {
  late ParkingFilter f;

  static const distances = <double?>[null, 500, 1000, 2000, 3000, 5000, 10000];
  static const prices = <double?>[null, 25, 50, 100, 200];

  @override
  void initState() {
    super.initState();
    f = AppScope.read(context).filter;
  }

  Widget _section(String title, Widget child, {String? hint}) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        if (hint != null) Text(hint, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final count = f.apply(c.all, origin: c.center).length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
          child: Row(
            children: [
              const Text('Filtreler', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(onPressed: () => setState(() => f = f.reset()), child: const Text('Sıfırla')),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            children: [
              _section(
                'Otopark türü',
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in ParkingType.values)
                      FilterChip(
                        label: Text(t.label),
                        selected: f.types.contains(t),
                        onSelected: (on) => setState(() {
                          final s = {...f.types};
                          on ? s.add(t) : s.remove(t);
                          f = f.copyWith(types: s);
                        }),
                      ),
                  ],
                ),
              ),
              _section(
                'Mesafe',
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in distances)
                      ChoiceChip(
                        label: Text(d == null ? 'Tümü' : '≤ ${Fmt.distance(d)}'),
                        selected: f.maxDistanceM == d,
                        onSelected: (_) => setState(() => f = d == null ? f.copyWith(clearDistance: true) : f.copyWith(maxDistanceM: d)),
                      ),
                  ],
                ),
                hint: c.center == null ? 'Mesafe, konumunuza veya aradığınız yere göre hesaplanır.' : 'Merkez: ${c.centerLabel}',
              ),
              _section(
                'Saatlik fiyat',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in prices)
                          ChoiceChip(
                            label: Text(p == null ? 'Tümü' : '≤ ${Fmt.tl(p)}'),
                            selected: !f.onlyFree && f.maxHourlyPrice == p,
                            onSelected: (_) => setState(
                              () => f = p == null
                                  ? f.copyWith(clearPrice: true, onlyFree: false)
                                  : f.copyWith(maxHourlyPrice: p, onlyFree: false),
                            ),
                          ),
                        ChoiceChip(
                          label: const Text('Yalnızca ücretsiz'),
                          selected: f.onlyFree,
                          onSelected: (on) => setState(() => f = f.copyWith(onlyFree: on, clearPrice: true)),
                        ),
                      ],
                    ),
                    if (f.maxHourlyPrice != null)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: f.includeUnknownPrice,
                        onChanged: (v) => setState(() => f = f.copyWith(includeUnknownPrice: v)),
                        title: const Text('Fiyatı bilinmeyenleri de göster', style: TextStyle(fontSize: 14)),
                      ),
                  ],
                ),
                hint: 'Fiyatı kaynakta bulunmayan otoparklara tahmini ücret yazılmaz.',
              ),
              _section(
                'Doluluk',
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in OccupancyFilter.values)
                      ChoiceChip(
                        label: Text(o.label),
                        selected: f.occupancy == o,
                        onSelected: (_) => setState(() => f = f.copyWith(occupancy: o)),
                      ),
                  ],
                ),
                hint: 'Anlık doluluk yalnızca resmî veri sunan otoparklarda (şu an İstanbul İSPARK) vardır.',
              ),
              _section(
                'Sıralama',
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in ParkingSort.values)
                      ChoiceChip(
                        label: Text(s.label),
                        selected: f.sort == s,
                        onSelected: (_) => setState(() => f = f.copyWith(sort: s)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  c.setFilter(f);
                  widget.onDone();
                },
                child: Text(count == 0 ? 'Uygula (sonuç yok)' : '$count sonucu göster'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
