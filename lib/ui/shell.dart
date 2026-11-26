import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../domain/parking.dart';
import 'screens/desktop_explore.dart';
import 'screens/detail_screen.dart';
import 'screens/explore_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screens.dart';
import 'screens/manage_screen.dart';
import 'screens/settings_about.dart';
import 'widgets/common.dart';

enum Dest { home, map, list, favorites, history, manage, settings, about }

/// Uyarlanabilir kabuk: Android'de alt gezinme çubuğu (tek elle kullanım),
/// Windows'ta yan gezinme rayı ve geniş ekran yerleşimi.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _tab = 0;
  final _navKey = GlobalKey<NavigatorState>();

  bool get _wide => AppPlatform.isDesktop || MediaQuery.sizeOf(context).width >= 840;

  /// Otopark detayını platforma uygun biçimde açar.
  void openParking(Parking p) {
    final c = AppScope.read(context);
    if (_wide) {
      setState(() => _tab = 0);
      c.selected.value = p;
      c.cameraRequest.value = (p.location, 17);
    } else {
      DetailScreen.open(_navKey.currentContext ?? context, p);
    }
  }

  /// Programatik gezinme (öz-sınama modunda da kullanılır).
  void open(Dest d) {
    _navKey.currentState?.popUntil((r) => r.isFirst);
    if (_wide) {
      final i = switch (d) {
        Dest.home || Dest.map || Dest.list => 0,
        Dest.favorites => 1,
        Dest.history => 2,
        Dest.manage => 3,
        Dest.settings => 4,
        Dest.about => 5,
      };
      setState(() => _tab = i);
      return;
    }
    switch (d) {
      case Dest.home:
        setState(() => _tab = 0);
      case Dest.map:
        ExploreScreen.showList.value = false;
        setState(() => _tab = 1);
      case Dest.list:
        ExploreScreen.showList.value = true;
        setState(() => _tab = 1);
      case Dest.favorites:
        setState(() => _tab = 2);
      case Dest.history || Dest.manage || Dest.settings || Dest.about:
        setState(() => _tab = 3);
        WidgetsBinding.instance.addPostFrameCallback((_) => _pushMore(d));
    }
  }

  void openParkingDetailRoute(Parking p) => DetailScreen.open(_navKey.currentContext ?? context, p);

  void _pushMore(Dest d) {
    final nav = _navKey.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(builder: (_) => _screenFor(d)));
  }

  Widget _screenFor(Dest d) => switch (d) {
    Dest.history => HistoryScreen(onOpen: openParking),
    Dest.manage => ManageScreen(onOpen: openParking),
    Dest.settings => const SettingsScreen(),
    Dest.about => const AboutScreen(),
    _ => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) {
    return _wide ? _desktop() : _mobile();
  }

  // -------------------------------------------------------------- Android

  Widget _mobile() {
    final body = switch (_tab) {
      0 => HomeScreen(onOpenMap: () => open(Dest.map), onOpen: openParking),
      1 => ExploreScreen(onOpen: openParking),
      2 => FavoritesScreen(onOpen: openParking),
      _ => _MoreScreen(onTap: _pushMore),
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_navKey.currentState?.canPop() ?? false) {
          _navKey.currentState!.pop();
        } else if (_tab != 0) {
          setState(() => _tab = 0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: Navigator(
          key: _navKey,
          pages: [MaterialPage(key: ValueKey('tab$_tab'), child: body)],
          onDidRemovePage: (_) {},
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) {
            _navKey.currentState?.popUntil((r) => r.isFirst);
            setState(() => _tab = i);
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Ana sayfa'),
            NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map_rounded), label: 'Keşfet'),
            NavigationDestination(
              icon: Icon(Icons.favorite_border_rounded),
              selectedIcon: Icon(Icons.favorite_rounded),
              label: 'Favoriler',
            ),
            NavigationDestination(icon: Icon(Icons.menu_rounded), label: 'Daha fazla'),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- Windows

  Widget _desktop() {
    final body = switch (_tab) {
      0 => const DesktopExplore(),
      1 => FavoritesScreen(onOpen: openParking),
      2 => HistoryScreen(onOpen: openParking),
      3 => ManageScreen(onOpen: openParking),
      4 => const SettingsScreen(),
      _ => const AboutScreen(),
    };
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _tab,
            labelType: NavigationRailLabelType.all,
            minWidth: 84,
            leading: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: BrandLogo(size: 40, showText: false)),
            onDestinationSelected: (i) {
              _navKey.currentState?.popUntil((r) => r.isFirst);
              setState(() => _tab = i);
            },
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map_rounded), label: Text('Keşfet')),
              NavigationRailDestination(
                icon: Icon(Icons.favorite_border_rounded),
                selectedIcon: Icon(Icons.favorite_rounded),
                label: Text('Favoriler'),
              ),
              NavigationRailDestination(icon: Icon(Icons.history_rounded), label: Text('Geçmiş')),
              NavigationRailDestination(
                icon: Icon(Icons.edit_location_alt_outlined),
                selectedIcon: Icon(Icons.edit_location_alt_rounded),
                label: Text('Yönetim'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: Text('Ayarlar'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.info_outline_rounded),
                selectedIcon: Icon(Icons.info_rounded),
                label: Text('Hakkında'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Navigator(
              key: _navKey,
              pages: [MaterialPage(key: ValueKey('desk$_tab'), child: body)],
              onDidRemovePage: (_) {},
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreScreen extends StatelessWidget {
  const _MoreScreen({required this.onTap});

  final ValueChanged<Dest> onTap;

  @override
  Widget build(BuildContext context) {
    Widget item(Dest d, IconData icon, String title, String sub) => Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => onTap(d),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Daha fazla')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          item(Dest.history, Icons.history_rounded, 'Geçmiş', 'Son görüntülenenler ve ziyaret geçmişi'),
          item(Dest.manage, Icons.edit_location_alt_outlined, 'Otopark yönetimi', 'Yerel otopark ekle, düzenle, sil'),
          item(Dest.settings, Icons.settings_outlined, 'Ayarlar', 'Harita, arama yarıçapı, güncelleme, veriler'),
          item(Dest.about, Icons.info_outline_rounded, 'Hakkında', 'Sürüm, geliştirici, veri kaynakları'),
        ],
      ),
    );
  }
}
