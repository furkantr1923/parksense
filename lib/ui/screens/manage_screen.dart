import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/geo.dart';
import '../../domain/data_source.dart';
import '../../domain/parking.dart';
import '../../domain/validation.dart';
import '../widgets/common.dart';
import '../widgets/parking_map.dart';

/// Yerel otopark yönetimi: ekle, düzenle, sil, fiyat/kapasite güncelle.
class ManageScreen extends StatelessWidget {
  const ManageScreen({super.key, required this.onOpen});

  final ValueChanged<Parking> onOpen;

  Future<void> _delete(BuildContext context, Parking p) async {
    final c = AppScope.read(context);
    final deps = c.db.dependentsOf(p.id);
    final extra = [
      if (deps.favorites > 0) 'favori kaydı',
      if (deps.visits > 0) '${deps.visits} ziyaret kaydı',
      if (deps.ratings > 0) 'puanınız',
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Otopark silinsin mi?'),
        content: Text(
          '"${p.name}" kalıcı olarak silinecek.'
          '${extra.isEmpty ? '' : '\n\nBu kayda bağlı ${extra.join(', ')} da silinecek.'}\n\nBu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.full),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok == true) {
      c.deleteLocal(p.id);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Otopark silindi.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final items = c.db.localParkings();
    return Scaffold(
      appBar: AppBar(title: const Text('Otopark yönetimi')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ParkingFormScreen.open(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Otopark ekle'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          const NoticeBanner(
            text:
                'Bu ekrandan eklenen kayıtlar yalnızca bu cihazda saklanır ve diğer cihazlara otomatik olarak aktarılmaz. '
                'Kayıtlar uygulamada "Yerel kayıt (doğrulanmamış)" etiketiyle gösterilir.',
            icon: Icons.phonelink_lock_outlined,
            color: AppColors.local,
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const EmptyState(
              icon: Icons.add_location_alt_outlined,
              title: 'Yerel otopark kaydı yok',
              message: 'İşlettiğiniz veya bildiğiniz bir otoparkı fiyat ve kapasite bilgileriyle ekleyebilirsiniz.',
            )
          else
            for (final p in items)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        [p.type.label, if (p.district != null) p.district!, if (p.city != null) p.city!].join(' · '),
                        style: const TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Kapasite: ${p.capacity == null ? '—' : Fmt.integer(p.capacity!)} · ${priceSummary(p)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      if (p.updatedAt != null)
                        Text('Güncelleme: ${Fmt.dateTime(p.updatedAt!)}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () => onOpen(p),
                            icon: const Icon(Icons.visibility_outlined, size: 18),
                            label: const Text('Görüntüle'),
                          ),
                          TextButton.icon(
                            onPressed: () => ParkingFormScreen.open(context, existing: p),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Düzenle'),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: AppColors.full),
                            onPressed: () => _delete(context, p),
                            icon: const Icon(Icons.delete_outline_rounded, size: 18),
                            label: const Text('Sil'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class ParkingFormScreen extends StatefulWidget {
  const ParkingFormScreen({super.key, this.existing});

  final Parking? existing;

  static Future<void> open(BuildContext context, {Parking? existing}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ParkingFormScreen(existing: existing)));

  @override
  State<ParkingFormScreen> createState() => _ParkingFormScreenState();
}

class _ParkingFormScreenState extends State<ParkingFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> f;
  ParkingType _type = ParkingType.open;
  bool _dirty = false;
  String? _coordWarning;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    final c = AppScope.read(context);
    final center = c.center;
    String n(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString());
    f = {
      'name': TextEditingController(text: p?.name ?? ''),
      'address': TextEditingController(text: p?.address ?? ''),
      'city': TextEditingController(text: p?.city ?? ''),
      'district': TextEditingController(text: p?.district ?? ''),
      'lat': TextEditingController(text: p != null ? p.location.lat.toStringAsFixed(6) : (center?.lat.toStringAsFixed(6) ?? '')),
      'lng': TextEditingController(text: p != null ? p.location.lng.toStringAsFixed(6) : (center?.lng.toStringAsFixed(6) ?? '')),
      'capacity': TextEditingController(text: p?.capacity?.toString() ?? ''),
      'hourly': TextEditingController(text: n(p?.price?.hourly)),
      'daily': TextEditingController(text: n(p?.price?.daily)),
      'monthly': TextEditingController(text: n(p?.price?.monthly)),
      'hours': TextEditingController(text: p?.openingHours ?? ''),
      'phone': TextEditingController(text: p?.phone ?? ''),
      'website': TextEditingController(text: p?.website ?? ''),
      'source': TextEditingController(text: p == null ? '' : (c.db.sourceNote(p.id) ?? '')),
    };
    _type = p?.type ?? ParkingType.open;
    for (final ctrl in f.values) {
      ctrl.addListener(() => _dirty = true);
    }
  }

  @override
  void dispose() {
    for (final ctrl in f.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  String? _t(String k) => f[k]!.text.trim().isEmpty ? null : f[k]!.text.trim();

  void _save() {
    setState(() => _coordWarning = null);
    if (!_form.currentState!.validate()) return;
    final lat = Fmt.parseNumber(f['lat']!.text)!;
    final lng = Fmt.parseNumber(f['lng']!.text)!;
    final outside = Validators.inTurkey(lat, lng);
    if (outside != null) {
      setState(() => _coordWarning = outside);
      return;
    }
    final now = DateTime.now().toUtc();
    final hourly = Fmt.parseNumber(_t('hourly'));
    final daily = Fmt.parseNumber(_t('daily'));
    final monthly = Fmt.parseNumber(_t('monthly'));
    final price = (hourly == null && daily == null && monthly == null)
        ? null
        : PriceInfo(hourly: hourly, daily: daily, monthly: monthly, sourceId: DataSources.local.id, updatedAt: now);
    final id = widget.existing?.id ?? 'local:${now.microsecondsSinceEpoch}-${math.Random().nextInt(1 << 20)}';
    final p = Parking(
      id: id,
      sourceId: DataSources.local.id,
      name: f['name']!.text.trim(),
      location: GeoPoint(lat, lng),
      address: _t('address'),
      city: _t('city'),
      district: _t('district'),
      type: _type,
      capacity: int.tryParse(f['capacity']!.text.trim()),
      price: price,
      openingHours: _t('hours'),
      phone: _t('phone'),
      website: _t('website'),
      updatedAt: now,
      fetchedAt: now,
    );
    try {
      AppScope.read(context).saveLocal(p, f['source']!.text.trim());
      _dirty = false;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.existing == null ? 'Otopark eklendi.' : 'Değişiklikler kaydedildi.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    }
  }

  Future<void> _pickOnMap() async {
    final lat = Fmt.parseNumber(f['lat']!.text);
    final lng = Fmt.parseNumber(f['lng']!.text);
    final start = (lat != null && lng != null) ? GeoPoint(lat, lng) : (AppScope.read(context).center ?? const GeoPoint(41.0369, 28.985));
    final picked = await Navigator.of(context).push<GeoPoint>(MaterialPageRoute(builder: (_) => _CoordinatePicker(start: start)));
    if (picked != null) {
      f['lat']!.text = picked.lat.toStringAsFixed(6);
      f['lng']!.text = picked.lng.toStringAsFixed(6);
    }
  }

  Widget _field(
    String key,
    String label, {
    String? Function(String?)? validator,
    TextInputType? keyboard,
    String? hint,
    String? suffix,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: f[key],
        validator: validator,
        keyboardType: keyboard,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, hintText: hint, suffixText: suffix),
        autovalidateMode: AutovalidateMode.onUserInteraction,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const num = TextInputType.numberWithOptions(decimal: true, signed: true);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Kaydedilmemiş değişiklikler'),
            content: const Text('Değişiklikleri kaydetmeden çıkmak istiyor musunuz?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Düzenlemeye dön')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Çık')),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          _dirty = false;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.existing == null ? 'Otopark ekle' : 'Otoparkı düzenle'),
          actions: [TextButton(onPressed: _save, child: const Text('Kaydet'))],
        ),
        body: Form(
          key: _form,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  const Text('Genel', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 10),
                  _field('name', 'Otopark adı *', validator: Validators.name),
                  DropdownButtonFormField<ParkingType>(
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: 'Otopark türü'),
                    items: [for (final t in ParkingType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                    onChanged: (t) => setState(() {
                      _type = t ?? ParkingType.unknown;
                      _dirty = true;
                    }),
                  ),
                  const SizedBox(height: 12),
                  _field(
                    'capacity',
                    'Toplam kapasite',
                    validator: Validators.optionalCapacity,
                    keyboard: TextInputType.number,
                    suffix: 'araç',
                  ),
                  _field('hours', 'Çalışma saatleri', hint: 'ör. 7/24 veya Pzt–Cmt 08:00–22:00'),
                  const SizedBox(height: 8),
                  const Text('Konum', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 10),
                  _field('address', 'Adres'),
                  Row(
                    children: [
                      Expanded(child: _field('district', 'İlçe')),
                      const SizedBox(width: 12),
                      Expanded(child: _field('city', 'Şehir')),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _field('lat', 'Enlem *', validator: Validators.latitude, keyboard: num),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field('lng', 'Boylam *', validator: Validators.longitude, keyboard: num),
                      ),
                    ],
                  ),
                  if (_coordWarning != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: NoticeBanner(text: _coordWarning!, color: AppColors.full, icon: Icons.error_outline),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _pickOnMap,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Haritadan seç'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Fiyatlar (₺)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const Text(
                    'Bilmediğiniz alanları boş bırakın; boş alanlar "Bilgi mevcut değil" olarak gösterilir.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _field('hourly', 'Saatlik', validator: Validators.optionalPrice, keyboard: num, suffix: '₺'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field('daily', 'Günlük', validator: Validators.optionalPrice, keyboard: num, suffix: '₺'),
                      ),
                    ],
                  ),
                  _field('monthly', 'Abonelik (aylık)', validator: Validators.optionalPrice, keyboard: num, suffix: '₺'),
                  const SizedBox(height: 8),
                  const Text('İletişim', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 10),
                  _field('phone', 'Telefon', validator: Validators.optionalPhone, keyboard: TextInputType.phone),
                  _field('website', 'Web sitesi', validator: Validators.optionalUrl, keyboard: TextInputType.url, hint: 'https://'),
                  const SizedBox(height: 8),
                  const Text('Veri kaynağı', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 10),
                  _field(
                    'source',
                    'Bilginin kaynağı *',
                    validator: Validators.sourceNote,
                    hint: 'ör. İşletme beyanı, yerinde gözlem (26.11.2026)',
                    maxLines: 2,
                  ),
                  const NoticeBanner(
                    text:
                        'Kayıt yalnızca bu cihazda saklanır, diğer cihazlara aktarılmaz. Anlık doluluk elle girilemez; '
                        'doluluk yalnızca doğrulanmış kaynaklardan gösterilir.',
                    icon: Icons.info_outline_rounded,
                    color: AppColors.local,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Kaydet')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CoordinatePicker extends StatefulWidget {
  const _CoordinatePicker({required this.start});

  final GeoPoint start;

  @override
  State<_CoordinatePicker> createState() => _CoordinatePickerState();
}

class _CoordinatePickerState extends State<_CoordinatePicker> {
  late GeoPoint p = widget.start;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Konumu seçin'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, p), child: const Text('Tamam'))],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: ll(widget.start),
              initialZoom: 16,
              onTap: (_, point) => setState(() => p = gp(point)),
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [
              baseTiles(c.tileSource),
              MarkerLayer(
                markers: [
                  Marker(
                    point: ll(p),
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.location_on_rounded, color: AppColors.local, size: 40),
                  ),
                ],
              ),
              mapAttribution(c.tileSource),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: NoticeBanner(
              text: 'Haritaya dokunarak konumu seçin.\n${p.lat.toStringAsFixed(6)}, ${p.lng.toStringAsFixed(6)}',
              icon: Icons.touch_app_outlined,
            ),
          ),
        ],
      ),
    );
  }
}
