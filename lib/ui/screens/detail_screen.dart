import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../domain/data_source.dart';
import '../../domain/parking.dart';
import '../../services/navigation_service.dart';
import '../widgets/common.dart';
import '../widgets/parking_map.dart';

class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.parking});

  final Parking parking;

  static Future<void> open(BuildContext context, Parking p) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailScreen(parking: p)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Otopark detayı')),
      body: DetailView(parking: parking),
    );
  }
}

/// Otopark detayı. Mobilde tam sayfa, Windows'ta yan panel olarak kullanılır.
class DetailView extends StatefulWidget {
  const DetailView({super.key, required this.parking, this.onClose});

  final Parking parking;
  final VoidCallback? onClose;

  @override
  State<DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<DetailView> {
  late Parking p = widget.parking;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DetailView old) {
    super.didUpdateWidget(old);
    if (old.parking.id != widget.parking.id) {
      p = widget.parking;
      _load();
    }
  }

  Future<void> _load() async {
    final c = AppScope.read(context);
    p = c.live(widget.parking);
    c.recordView(p);
    setState(() => loading = true);
    final rich = await c.details(p);
    if (!mounted || rich.id != widget.parking.id) return;
    setState(() {
      p = rich;
      loading = false;
    });
  }

  Future<void> _navigate() async {
    final c = AppScope.read(context);
    final r = await c.navigate(p);
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    if (r == NavResult.failed) {
      m.showSnackBar(const SnackBar(content: Text('Yol tarifi açılamadı. Google Maps veya bir web tarayıcısı bulunamadı.')));
      return;
    }
    m.showSnackBar(
      SnackBar(
        content: Text(r == NavResult.openedApp ? 'Google Maps açıldı.' : 'Yol tarifi tarayıcıda açıldı.'),
        action: SnackBarAction(label: 'Ziyaret olarak kaydet', onPressed: () => c.recordVisit(p)),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final fav = c.isFavorite(p);
    final d = c.distanceTo(p);
    final stars = c.ratings[p.id] ?? 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (widget.onClose != null)
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(tooltip: 'Kapat', onPressed: widget.onClose, icon: const Icon(Icons.close_rounded)),
          ),
        Text(
          p.name,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.2,
            color: p.nameIsGenerated ? AppColors.muted : AppColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Pill(p.type.label, icon: typeIcon(p.type), color: AppColors.primary),
            if (p.isOpenNow == true) const Pill('Açık', color: AppColors.free, icon: Icons.schedule_rounded),
            if (p.isOpenNow == false) const Pill('Kapalı', color: AppColors.full, icon: Icons.schedule_rounded),
            SourceBadge(p.source),
            if (d != null) Pill(Fmt.distance(d), icon: Icons.near_me_outlined),
            if (loading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
        const SizedBox(height: 16),
        MiniMap(point: p.location),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: FilledButton.icon(onPressed: _navigate, icon: const Icon(Icons.directions_rounded), label: const Text('Yol tarifi')),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: () => c.toggleFavorite(p),
                icon: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: fav ? AppColors.full : null),
                label: Text(fav ? 'Favoride' : 'Favori'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            c.recordVisit(p);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ziyaret geçmişine eklendi.')));
          },
          icon: const Icon(Icons.history_rounded),
          label: const Text('Ziyaret ettim olarak işaretle'),
        ),
        const SizedBox(height: 16),
        _Card(
          title: 'Doluluk',
          icon: Icons.donut_large_rounded,
          children: [
            OccupancyView(p),
            if (p.hasLiveOccupancy) ...[
              const SizedBox(height: 10),
              Text(
                '${p.occupancy!.observedAtIsFetchTime ? 'Veri alınma zamanı' : 'Kaynağın güncelleme zamanı'}: ${Fmt.dateTime(p.occupancy!.observedAt)} · Kaynak: ${p.source.name}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
            const SizedBox(height: 10),
            _Row('Toplam kapasite', p.totalCapacity == null ? null : '${Fmt.integer(p.totalCapacity!)} araç'),
            _Row('Boş kapasite', p.hasLiveOccupancy ? Fmt.integer(p.occupancy!.free) : null),
            _Row('Doluluk oranı', p.hasLiveOccupancy && p.occupancy!.ratio != null ? Fmt.percent(p.occupancy!.ratio!) : null),
          ],
        ),
        _Card(title: 'Fiyatlar', icon: Icons.payments_outlined, children: _priceRows(p)),
        _Card(
          title: 'Bilgiler',
          icon: Icons.info_outline_rounded,
          children: [
            _Row('Adres', p.address),
            _Row(
              'İlçe / Şehir',
              [p.district, p.city].whereType<String>().join(' / ').isEmpty ? null : [p.district, p.city].whereType<String>().join(' / '),
            ),
            _Row('Konum', '${p.location.lat.toStringAsFixed(5)}, ${p.location.lng.toStringAsFixed(5)}'),
            _Row('Çalışma saatleri', p.openingHours),
            _Row('İşletmeci', p.operatorName),
            _Row('Erişim', p.accessNote),
            _Row('Telefon', p.phone, onTap: p.phone == null ? null : () => _open(NavigationService.phoneUri(p.phone!))),
            _Row('Web sitesi', p.website, onTap: p.website == null ? null : () => _open(NavigationService.websiteUri(p.website!))),
            _Row('Erişilebilirlik', p.accessibility),
            _Row('Olanaklar', p.amenities.isEmpty ? null : p.amenities.join(', ')),
          ],
        ),
        _Card(
          title: 'Fotoğraflar',
          icon: Icons.photo_outlined,
          children: [
            if (p.photos.isEmpty)
              const Text('Fotoğraf mevcut değil', style: TextStyle(color: AppColors.muted))
            else
              SizedBox(
                height: 140,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: p.photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      p.photos[i],
                      width: 200,
                      fit: BoxFit.cover,
                      cacheWidth: 400,
                      errorBuilder: (_, _, _) => Container(
                        width: 200,
                        color: AppColors.line,
                        alignment: Alignment.center,
                        child: const Text('Fotoğraf yüklenemedi', style: TextStyle(color: AppColors.muted)),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        _Card(
          title: 'Puanınız',
          icon: Icons.star_outline_rounded,
          children: [
            StarRating(value: stars, onChanged: (v) => c.rate(p, v)),
            const SizedBox(height: 6),
            Text(
              stars == 0 ? 'Henüz puan vermediniz. Puanınız yalnızca bu cihazda saklanır.' : '$stars / 5 · yalnızca bu cihazda saklanır.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ],
        ),
        _Card(
          title: 'Veri kaynağı',
          icon: Icons.fact_check_outlined,
          children: [
            _Row('Kaynak', p.source.name),
            _Row('Güvenilirlik', p.source.reliability.label),
            _Row('Lisans', p.source.license),
            if (p.isLocal) _Row('Kaynak notu', c.db.sourceNote(p.id)),
            _Row('Son güncelleme', p.updatedAt == null ? null : Fmt.dateTime(p.updatedAt!)),
            _Row('Alınma zamanı', p.fetchedAt == null ? null : Fmt.dateTime(p.fetchedAt!)),
            const SizedBox(height: 8),
            NoticeBanner(
              text: p.source.reliability.explanation,
              icon: p.source.reliability == Reliability.official ? Icons.verified_outlined : Icons.warning_amber_rounded,
              color: p.source.reliability == Reliability.official ? AppColors.free : AppColors.busy,
            ),
            if (p.sourceRef != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _open(Uri.parse(p.sourceRef!)),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Kaynaktaki kaydı aç'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _open(Uri? uri) async {
    final ok = uri != null && await AppScope.read(context).nav.open(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bağlantı açılamadı.')));
    }
  }

  List<Widget> _priceRows(Parking p) {
    final pr = p.price;
    if (pr == null || !pr.hasAny) {
      return const [
        Text('Fiyat bilgisi mevcut değil', style: TextStyle(color: AppColors.muted)),
        SizedBox(height: 4),
        Text(
          'Bu otopark için doğrulanmış bir tarife kaynağı bulunamadı; tahmini ücret gösterilmez.',
          style: TextStyle(fontSize: 12.5, color: AppColors.muted),
        ),
      ];
    }
    return [
      if (pr.isFree == true)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Pill('Ücretsiz', color: AppColors.free, icon: Icons.check_rounded),
        ),
      _Row('Saatlik', pr.hourly == null ? null : Fmt.tl(pr.hourly!)),
      _Row('Günlük', pr.daily == null ? null : Fmt.tl(pr.daily!)),
      _Row('Abonelik (aylık)', pr.monthly == null ? null : Fmt.tl(pr.monthly!)),
      if (pr.freeMinutes != null) _Row('Ücretsiz süre', 'İlk ${pr.freeMinutes} dakika'),
      if (pr.isFree == false && !pr.hasAnyAmount) const _Row('Durum', 'Ücretli (tutar kaynakta belirtilmemiş)'),
      if (pr.tiers.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('Tarife', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 4),
        for (final t in pr.tiers) _Row(t.label, Fmt.tl(t.amount), dense: true),
      ],
      if (pr.rawText != null) ...[
        const SizedBox(height: 6),
        Text('Kaynaktaki ifade: ${pr.rawText}', style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
      ],
      const SizedBox(height: 8),
      Text(
        'Kaynak: ${DataSources.byId(pr.sourceId).name}${pr.updatedAt != null ? ' · ${Fmt.dateTime(pr.updatedAt!)}' : ''}',
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
    ];
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Etiket–değer satırı; değer yoksa "Bilgi mevcut değil".
class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.onTap, this.dense = false});

  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final has = value != null && value!.trim().isNotEmpty;
    return InkWell(
      onTap: has ? onTap : null,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 3 : 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13.5)),
            ),
            Expanded(
              child: Text(
                has ? value! : 'Bilgi mevcut değil',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: has ? FontWeight.w600 : FontWeight.w400,
                  color: has ? (onTap != null ? AppColors.primary : AppColors.ink) : AppColors.unknown,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
