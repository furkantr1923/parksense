import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../domain/parking.dart';
import '../widgets/common.dart';
import '../widgets/parking_card.dart';

/// Favoriler — yalnızca bu cihazda (SQLite) tutulur.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key, required this.onOpen});

  final ValueChanged<Parking> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final items = c.db.favorites().map(c.live).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Favoriler')),
      body: items.isEmpty
          ? const EmptyState(
              icon: Icons.favorite_border_rounded,
              title: 'Henüz favori yok',
              message: 'Bir otoparkın detayında veya listede kalp simgesine dokunarak favorilere ekleyebilirsiniz.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => i == 0
                  ? const Text('Favoriler yalnızca bu cihazda saklanır.', style: TextStyle(color: AppColors.muted, fontSize: 12.5))
                  : ParkingCard(parking: items[i - 1], onTap: () => onOpen(items[i - 1])),
            ),
    );
  }
}

/// Son görüntülenenler + ziyaret geçmişi.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.onOpen});

  final ValueChanged<Parking> onOpen;

  Future<bool> _confirm(BuildContext context, String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.full),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Temizle'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final recent = c.db.recent();
    final visits = c.db.visits();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Geçmiş'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Son görüntülenenler'),
              Tab(text: 'Ziyaret geçmişi'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            recent.isEmpty
                ? const EmptyState(icon: Icons.visibility_outlined, title: 'Henüz görüntülenen otopark yok')
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () async {
                            if (await _confirm(context, 'Son görüntülenenler temizlensin mi?', 'Bu işlem geri alınamaz.')) {
                              c.db.clearRecent();
                              c.touch();
                            }
                          },
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: const Text('Temizle'),
                        ),
                      ),
                      for (final (p, at) in recent)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 4),
                                child: Text(Fmt.relative(at), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                              ),
                              ParkingCard(parking: c.live(p), onTap: () => onOpen(c.live(p))),
                            ],
                          ),
                        ),
                    ],
                  ),
            visits.isEmpty
                ? const EmptyState(
                    icon: Icons.history_rounded,
                    title: 'Ziyaret geçmişi boş',
                    message: 'Detay sayfasındaki "Ziyaret ettim" düğmesiyle veya yol tarifinden sonra kayıt ekleyebilirsiniz.',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () async {
                            if (await _confirm(
                              context,
                              'Ziyaret geçmişi silinsin mi?',
                              '${visits.length} kayıt kalıcı olarak silinecek.',
                            )) {
                              c.db.clearVisits();
                              c.touch();
                            }
                          },
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: const Text('Tümünü sil'),
                        ),
                      ),
                      for (final (v, p) in visits)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.flag_outlined, color: AppColors.primary),
                            title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(Fmt.dateTime(v.visitedAt)),
                            onTap: () => onOpen(c.live(p)),
                            trailing: IconButton(
                              tooltip: 'Kaydı sil',
                              onPressed: () {
                                c.db.deleteVisit(v.id);
                                c.touch();
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ),
                        ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
