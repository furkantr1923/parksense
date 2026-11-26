import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_info.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/geo.dart';
import '../../domain/clustering.dart';
import '../../domain/parking.dart';
import '../../state/app_controller.dart';

LatLng ll(GeoPoint p) => LatLng(p.lat, p.lng);
GeoPoint gp(LatLng p) => GeoPoint(p.latitude, p.longitude);

/// Testlerde ağ erişimi olmadığından döşeme katmanı kapatılabilir.
class MapConfig {
  MapConfig._();
  static bool tilesEnabled = true;
}

/// Altlık harita katmanı. API anahtarı gerektirmez; döşemeler diske
/// önbelleklenir (flutter_map yerleşik önbelleği).
Widget baseTiles(TileSource source, {ErrorTileCallBack? onError}) {
  if (!MapConfig.tilesEnabled) return const SizedBox.shrink();
  return switch (source) {
    TileSource.carto => TileLayer(
      urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
      subdomains: const ['a', 'b', 'c', 'd'],
      retinaMode: false,
      userAgentPackageName: AppInfo.packageName,
      maxNativeZoom: 19,
      errorTileCallback: onError,
    ),
    TileSource.osm => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: AppInfo.packageName,
      maxNativeZoom: 19,
      errorTileCallback: onError,
    ),
  };
}

/// Zorunlu harita atfı (OSM/CARTO). Dar ekranlarda satır kaydırır; dokununca
/// OpenStreetMap telif sayfası açılır.
Widget mapAttribution(TileSource source) => Align(
  alignment: Alignment.bottomLeft,
  child: GestureDetector(
    onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'), mode: LaunchMode.externalApplication),
    child: Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      constraints: const BoxConstraints(maxWidth: 230),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(4)),
      child: Text(
        source == TileSource.carto ? '© OpenStreetMap katkıda bulunanlar © CARTO' : '© OpenStreetMap katkıda bulunanlar',
        style: const TextStyle(fontSize: 10.5, color: Color(0xFF334155)),
      ),
    ),
  ),
);

/// Etkileşimli otopark haritası: kümelenmiş işaretler, seçim, konum,
/// yakınlaştırma düğmeleri ve "Bu bölgede ara".
class ParkingMap extends StatefulWidget {
  const ParkingMap({
    super.key,
    required this.items,
    required this.onSelect,
    this.selectedId,
    this.showControls = true,
    this.bottomPadding = 0,
  });

  final List<Parking> items;
  final ValueChanged<Parking> onSelect;
  final String? selectedId;
  final bool showControls;
  final double bottomPadding;

  @override
  State<ParkingMap> createState() => _ParkingMapState();
}

class _ParkingMapState extends State<ParkingMap> {
  final _map = MapController();
  bool _ready = false;
  double _zoom = 14;
  LatLngBounds? _bounds;
  LatLng? _camCenter;
  Timer? _debounce;
  bool _tileError = false;
  int _tileKey = 0;
  AppController? _c;

  static const defaultCenter = LatLng(39.0, 35.2); // Türkiye

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = AppScope.read(context);
    if (_c != c) {
      _c?.cameraRequest.removeListener(_onCameraRequest);
      _c = c..cameraRequest.addListener(_onCameraRequest);
    }
  }

  @override
  void dispose() {
    _c?.cameraRequest.removeListener(_onCameraRequest);
    _debounce?.cancel();
    super.dispose();
  }

  void _onCameraRequest() {
    final r = _c?.cameraRequest.value;
    if (r == null || !_ready) return;
    _map.move(ll(r.$1), r.$2);
  }

  void _onPosition(MapCamera cam, bool gesture) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      setState(() {
        _zoom = cam.zoom;
        _bounds = cam.visibleBounds;
        _camCenter = cam.center;
      });
    });
  }

  void _onTileError(TileImage tile, Object error, StackTrace? st) {
    if (_tileError) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _tileError = true);
    });
  }

  List<MarkerCluster> _clusters() {
    final b = _bounds;
    var items = widget.items;
    if (b != null) {
      // Yalnızca görünen alan (+%25 pay) işlenir.
      final padLat = (b.north - b.south) * 0.25, padLng = (b.east - b.west) * 0.25;
      items = items
          .where(
            (p) =>
                p.location.lat >= b.south - padLat &&
                p.location.lat <= b.north + padLat &&
                p.location.lng >= b.west - padLng &&
                p.location.lng <= b.east + padLng,
          )
          .toList();
    }
    return Clusterer.cluster(items, _zoom);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final req = c.cameraRequest.value;
    final initial = req != null ? ll(req.$1) : (c.center != null ? ll(c.center!) : defaultCenter);
    final initialZoom = req?.$2 ?? (c.center != null ? 15.0 : 5.6);
    final clusters = _clusters();
    final showSearchHere =
        _camCenter != null &&
        c.loadedArea != null &&
        _zoom >= 12 &&
        Geo.distanceM(gp(_camCenter!), c.loadedArea!.center) > c.loadedArea!.radiusM * 0.45;

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: initial,
            initialZoom: initialZoom,
            minZoom: 5,
            maxZoom: 19,
            backgroundColor: const Color(0xFFEFF2F6),
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onMapReady: () {
              _ready = true;
              final cam = _map.camera;
              _onPosition(cam, false);
            },
            onPositionChanged: _onPosition,
          ),
          children: [
            KeyedSubtree(
              key: ValueKey('tiles-${c.tileSource.name}-$_tileKey'),
              child: baseTiles(c.tileSource, onError: _onTileError),
            ),
            if (c.center != null && c.centerIsUser)
              CircleLayer(
                circles: [
                  CircleMarker(point: ll(c.center!), radius: 9, color: AppColors.primary, borderColor: Colors.white, borderStrokeWidth: 3),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final cl in clusters)
                  if (cl.isSingle)
                    Marker(
                      point: ll(cl.center),
                      width: cl.items.first.id == widget.selectedId ? 46 : 34,
                      height: cl.items.first.id == widget.selectedId ? 46 : 34,
                      child: _ParkingPin(
                        parking: cl.items.first,
                        selected: cl.items.first.id == widget.selectedId,
                        onTap: () => widget.onSelect(cl.items.first),
                      ),
                    )
                  else
                    Marker(
                      point: ll(cl.center),
                      width: 44,
                      height: 44,
                      child: _ClusterPin(count: cl.items.length, onTap: () => _map.move(ll(cl.center), (_zoom + 2).clamp(5, 18))),
                    ),
              ],
            ),
            mapAttribution(c.tileSource),
          ],
        ),
        if (_tileError)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Material(
              color: Colors.white,
              elevation: 2,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off_rounded, color: AppColors.busy, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Harita görüntüsü yüklenemedi. Bağlantınızı kontrol edin.', style: TextStyle(fontSize: 13))),
                    TextButton(
                      onPressed: () => setState(() {
                        _tileError = false;
                        _tileKey++;
                      }),
                      child: const Text('Tekrar dene'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (showSearchHere)
          Positioned(
            top: _tileError ? 70 : 14,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, elevation: 2, minimumSize: const Size(0, 40)),
                onPressed: () => c.searchHere(gp(_camCenter!)),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Bu bölgede ara'),
              ),
            ),
          ),
        if (widget.showControls)
          Positioned(
            right: 12,
            bottom: 28 + widget.bottomPadding,
            child: Column(
              children: [
                _MapButton(
                  icon: Icons.add,
                  tooltip: 'Yakınlaştır',
                  onTap: () => _map.move(_map.camera.center, (_map.camera.zoom + 1).clamp(5, 19)),
                ),
                const SizedBox(height: 8),
                _MapButton(
                  icon: Icons.remove,
                  tooltip: 'Uzaklaştır',
                  onTap: () => _map.move(_map.camera.center, (_map.camera.zoom - 1).clamp(5, 19)),
                ),
                const SizedBox(height: 8),
                _MapButton(
                  icon: c.locating ? Icons.more_horiz : Icons.my_location_rounded,
                  tooltip: 'Konumumu göster',
                  color: c.centerIsUser ? AppColors.primary : AppColors.ink,
                  onTap: () async {
                    final status = await c.useMyLocation();
                    if (!context.mounted || status.message.isEmpty) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status.message)));
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.tooltip, required this.onTap, this.color = AppColors.ink});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(width: 44, height: 44, child: Icon(icon, color: color)),
          ),
        ),
      ),
    );
  }
}

class _ParkingPin extends StatelessWidget {
  const _ParkingPin({required this.parking, required this.selected, required this.onTap});

  final Parking parking;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = parking;
    final color = p.isLocal ? AppColors.local : AppColors.occupancy(p.hasLiveOccupancy ? p.occupancy!.ratio : null);
    return Semantics(
      button: true,
      label: p.name,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : color,
            borderRadius: BorderRadius.circular(selected ? 14 : 10),
            border: Border.all(color: Colors.white, width: selected ? 3 : 2),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
          ),
          alignment: Alignment.center,
          child: Text(
            'P',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: selected ? 20 : 15),
          ),
        ),
      ),
    );
  }
}

class _ClusterPin extends StatelessWidget {
  const _ClusterPin({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primaryDark.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
        ),
        alignment: Alignment.center,
        child: Text(
          count > 99 ? '99+' : '$count',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ),
    );
  }
}

/// Detay sayfasındaki küçük, etkileşimsiz konum haritası.
class MiniMap extends StatelessWidget {
  const MiniMap({super.key, required this.point, this.height = 170});

  final GeoPoint point;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: ll(point),
            initialZoom: 16,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            baseTiles(c.tileSource),
            MarkerLayer(
              markers: [
                Marker(
                  point: ll(point),
                  width: 36,
                  height: 36,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'P',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
            mapAttribution(c.tileSource),
          ],
        ),
      ),
    );
  }
}
