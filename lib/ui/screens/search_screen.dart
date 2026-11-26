import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/failure.dart';
import '../../data/providers/geocoding.dart';
import '../../domain/parking.dart';
import '../widgets/common.dart';

/// Şehir/adres arama + yüklü otoparklar içinde ada göre arama.
///
/// Nominatim kullanım politikası gereği otomatik tamamlama yapılmaz;
/// istek yalnızca "Ara" ile gönderilir.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.onParking});

  final ValueChanged<Parking> onParking;

  static Future<void> open(BuildContext context, {required ValueChanged<Parking> onParking}) {
    final page = SearchScreen(onParking: onParking);
    if (MediaQuery.sizeOf(context).width >= 840) {
      return showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(40),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640), child: page),
        ),
      );
    }
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List<PlaceResult> _places = const [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.length < 2) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await AppScope.read(context).searchPlaces(q);
      if (mounted) setState(() => _places = r);
    } catch (e) {
      final f = AppFailure.from(e);
      if (mounted) {
        setState(() {
          _places = const [];
          _error = f.kind == FailureKind.notFound ? '"$q" için Türkiye\'de bir yer bulunamadı.' : f.message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _pick(PlaceResult p) {
    AppScope.read(context).selectPlace(p);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final q = _ctrl.text.trim().toLowerCase();
    final matches = q.length < 2 ? const <Parking>[] : c.all.where((p) => p.name.toLowerCase().contains(q)).take(8).toList();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: 'Şehir, ilçe, adres veya otopark adı',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: IconButton(tooltip: 'Ara', onPressed: _search, icon: const Icon(Icons.search_rounded)),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) NoticeBanner(text: _error!, icon: Icons.search_off_rounded, color: AppColors.busy),
          if (matches.isNotEmpty) ...[
            const SectionTitle('Yüklü otoparklarda'),
            for (final p in matches)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(typeIcon(p.type), color: AppColors.primary),
                title: Text(p.name),
                subtitle: Text([p.type.shortLabel, if (p.district != null) p.district!].join(' · ')),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onParking(p);
                },
              ),
            const SizedBox(height: 12),
          ],
          if (_places.isNotEmpty) ...[
            const SectionTitle('Yerler'),
            for (final p in _places)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined, color: AppColors.primary),
                title: Text(p.name),
                subtitle: p.detail.isEmpty ? null : Text(p.detail),
                onTap: () => _pick(p),
              ),
          ],
          if (_places.isEmpty && !_busy) ...[
            SectionTitle('Hızlı başlangıç', subtitle: q.length >= 2 ? 'Adres aramak için Enter\'a basın veya ara simgesine dokunun' : null),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final city in GeocodingService.cities)
                  ActionChip(
                    avatar: const Icon(Icons.location_city_rounded, size: 18),
                    label: Text(city.name),
                    onPressed: () => _pick(city),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Adres araması OpenStreetMap Nominatim ile yapılır.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ],
      ),
    );
  }
}
