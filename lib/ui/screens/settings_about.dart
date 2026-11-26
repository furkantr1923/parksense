import 'package:flutter/material.dart';

import '../../app/app_info.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../domain/data_source.dart';
import '../../services/update_service.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _endpoint = TextEditingController(text: AppScope.read(context).updateEndpoint);
  UpdateCheck? _check;
  bool _checking = false;

  @override
  void dispose() {
    _endpoint.dispose();
    super.dispose();
  }

  Future<void> _runCheck() async {
    final c = AppScope.read(context);
    c.setUpdateEndpoint(_endpoint.text);
    setState(() => _checking = true);
    final r = await const UpdateService().check(c.updateEndpoint);
    if (mounted) {
      setState(() {
        _check = r;
        _checking = false;
      });
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
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
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const SectionTitle('Harita'),
              Card(
                child: RadioGroup<TileSource>(
                  groupValue: c.tileSource,
                  onChanged: (v) => c.setTileSource(v!),
                  child: Column(
                    children: [for (final t in TileSource.values) RadioListTile<TileSource>(value: t, title: Text(t.label))],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SectionTitle('Arama yarıçapı', subtitle: 'Konum veya aranan yerin çevresinde: ${Fmt.distance(c.baseRadiusM)}'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Slider(
                    value: c.baseRadiusM.clamp(1000, 10000),
                    min: 1000,
                    max: 10000,
                    divisions: 9,
                    label: Fmt.distance(c.baseRadiusM),
                    onChanged: (v) => setState(() => c.baseRadiusM = v),
                    onChangeEnd: c.setBaseRadius,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const SectionTitle('Güncelleme', subtitle: 'Yalnızca siz denetlediğinizde sunucuya istek gönderilir'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Yüklü sürüm: ${AppInfo.version}', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _endpoint,
                        decoration: const InputDecoration(
                          labelText: 'Güncelleme uç noktası (GitHub Releases API)',
                          helperText: 'Boş bırakılırsa güncelleme denetimi kapalıdır.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: _checking ? null : _runCheck,
                            icon: _checking
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.system_update_alt_rounded, size: 18),
                            label: const Text('Güncellemeleri denetle'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(onPressed: () => _endpoint.text = AppInfo.defaultUpdateEndpoint, child: const Text('Varsayılan')),
                        ],
                      ),
                      if (_check != null) ...[
                        const SizedBox(height: 12),
                        NoticeBanner(
                          text: switch (_check!.state) {
                            UpdateState.notConfigured => _check!.message!,
                            UpdateState.upToDate => 'Uygulama güncel (sunucudaki son sürüm: ${_check!.latest}).',
                            UpdateState.available => 'Yeni sürüm mevcut: ${_check!.latest}',
                            UpdateState.error => 'Denetlenemedi: ${_check!.message}',
                          },
                          icon: _check!.state == UpdateState.available ? Icons.new_releases_outlined : Icons.info_outline,
                          color: _check!.state == UpdateState.error ? AppColors.busy : AppColors.primary,
                          action: _check!.url != null && _check!.state == UpdateState.available
                              ? TextButton(onPressed: () => c.nav.open(Uri.parse(_check!.url!)), child: const Text('İndir'))
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const SectionTitle('Veriler', subtitle: 'Tüm veriler yalnızca bu cihazdadır'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.cleaning_services_outlined),
                      title: const Text('Önbelleği temizle'),
                      subtitle: const Text('Kaydedilmiş otopark verilerini siler. Favoriler, geçmiş ve yerel kayıtlar korunur.'),
                      onTap: () {
                        final n = c.clearCache();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$n önbellek kaydı silindi.')));
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.restart_alt_rounded, color: AppColors.full),
                      title: const Text('Kişisel verileri sıfırla'),
                      subtitle: const Text('Favoriler, puanlar, son görüntülenenler ve ziyaret geçmişi silinir.'),
                      onTap: () async {
                        if (await _confirm(
                          'Kişisel veriler silinsin mi?',
                          'Favoriler, puanlar ve tüm geçmiş kalıcı olarak silinecek. Yerel otopark kayıtları korunur.',
                          'Sıfırla',
                        )) {
                          c.resetUserData();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kişisel veriler silindi.')));
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const NoticeBanner(
                text:
                    'Gizlilik: Hesap, bulut eşitleme, reklam ve analitik yoktur. Konumunuz yalnızca arama sırasında bellekte kullanılır, kaydedilmez.',
                icon: Icons.privacy_tip_outlined,
                color: AppColors.free,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final sources = c.db.dataSourceRows();
    return Scaffold(
      appBar: AppBar(title: const Text('Hakkında')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const BrandLogo(size: 56, subtitle: AppInfo.tagline),
                      const SizedBox(height: 16),
                      const Text('Sürüm ${AppInfo.version}', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      const Text(
                        'Türkiye genelindeki otoparkları harita üzerinde keşfetmenizi, fiyat ve doluluk bilgilerini incelemenizi '
                        've Google Maps ile yol tarifi almanızı sağlar. Ücretsizdir, reklam içermez, hesap gerektirmez.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, height: 1.45),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),
                      const Text('Geliştirici', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                      const SizedBox(height: 2),
                      const Text(AppInfo.developer, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => c.nav.open(Uri.parse(AppInfo.repoUrl)),
                        icon: const Icon(Icons.code_rounded, size: 18),
                        label: const Text('Kaynak kodu (GitHub)'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const SectionTitle('Veri kaynakları ve lisanslar'),
              for (final s in sources)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            SourceBadge(DataSources.byId('${s['id']}')),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('${s['description']}', style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4)),
                        const SizedBox(height: 6),
                        Text('Lisans: ${s['license']}', style: const TextStyle(fontSize: 12.5)),
                        Text('Anlık doluluk: ${s['realtime'] == 1 ? 'Var' : 'Yok'}', style: const TextStyle(fontSize: 12.5)),
                      ],
                    ),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Harita ve arama', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      const Text(
                        'Harita verisi © OpenStreetMap katkıda bulunanlar (ODbL). Harita görüntüleri: CARTO veya OpenStreetMap Vakfı döşeme sunucusu. '
                        'Adres araması: Nominatim. Yol tarifi: Google Maps.',
                        style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
                      ),
                      TextButton(
                        onPressed: () => c.nav.open(Uri.parse('https://www.openstreetmap.org/copyright')),
                        child: const Text('OpenStreetMap telif hakkı'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const NoticeBanner(
                text:
                    'İlk sürüm tüm Türkiye\'yi eksiksiz kapsadığını iddia etmez. Anlık doluluk yalnızca doğrulanmış kaynağı olan otoparklarda gösterilir; '
                    'fiyat ve kapasite bilgisi bulunmayan otoparklar için tahmini değer üretilmez.',
                icon: Icons.fact_check_outlined,
                color: AppColors.muted,
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text('© 2026 Furkan · MIT Lisansı', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
