// ByaheTayo — Flutter foundation.
//
// Single codebase for Android, iOS and tablets. This file owns only the
// app shell: Material 3 theme (ByaheTayo brand), adaptive navigation and
// tab state preservation. Feature ports (trip planner, fare calculator,
// Firebase, maps, friends) land in their own files under lib/features/
// and plug into the tab shells below — no tab is a dummy page, each shell
// names the real feature it will host.
//
// Wide layout (width >= 600, tablet portrait + landscape) uses a
// collapsible left sidebar (220dp expanded / 80dp collapsed, preference
// saved locally). Phones (width < 600) keep the bottom NavigationBar.
// The Account tab is a real dashboard in lib/features/account_tab.dart.
// The Fares tab is a real calculator in lib/features/fares_tab.dart.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/account_tab.dart';
import 'features/communities_tab.dart';
import 'features/fares_tab.dart';
import 'features/friends_tab.dart';
import 'features/map_tab.dart';
import 'features/student_tab.dart';
import 'features/student/student_theme.dart';

/// SharedPreferences key for the sidebar collapsed state.
const _sidebarCollapsedKey = 'byahetayo_sidebar_collapsed';

/// SharedPreferences key for the theme mode ('system', 'light', 'dark').
const _themeModeKey = 'byahetayo_theme_mode';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ByaheTayoApp(
      initialSidebarCollapsed: prefs.getBool(_sidebarCollapsedKey) ?? false,
      initialThemeMode: _themeModeFromString(prefs.getString(_themeModeKey)),
    ),
  );
}

ThemeMode _themeModeFromString(String? value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

// ---- Brand — Premium Dark Minimalist redesign (Oct 31 spec): emerald accent ----
const _primary = Color(0xFF16A34A);
const _primaryDark = Color(0xFF059669);
const _indicatorLight = Color(0xFFD1FAE5);
const _indicatorDark = Color(0xFF064E3B);
const _bgLight = Color(0xFFF1F5F9);
const _textDark = Color(0xFF0F172A);
const _textSecondary = Color(0xFF64748B);

ThemeData _lightTheme() {
  final scheme = const ColorScheme.light(
    primary: _primary,
    onPrimary: Colors.white,
    secondary: _primaryDark,
    surface: Colors.white,
    onSurface: _textDark,
    outline: Color(0xFFE2E8F0),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: _bgLight,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: _textDark,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: _textDark,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      elevation: 0,
      indicatorColor: _indicatorLight,
      iconTheme: const WidgetStatePropertyAll(IconThemeData(size: 24)),
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    // Premium Dark Minimalist card language (shared by every tab, and
    // the same language the Map sheet already uses): 16dp corners,
    // a subtle outline, no elevation shadow.
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: Color(0xFFE2E8F0)),
      ),
    ),
  );
}

ThemeData _darkTheme() {
  final scheme = const ColorScheme.dark(
    primary: Color(0xFF34D399),
    onPrimary: Color(0xFF052E16),
    secondary: Color(0xFF6EE7B7),
    surface: Color(0xFF1E2126),
    onSurface: Color(0xFFF1F5F9),
    outline: Color(0xFF33373E),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF17191D),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E2126),
      foregroundColor: Color(0xFFF1F5F9),
      elevation: 0,
      titleTextStyle: TextStyle(
        color: Color(0xFFF1F5F9),
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Color(0xFF1E2126),
      elevation: 0,
      indicatorColor: _indicatorDark,
      iconTheme: WidgetStatePropertyAll(IconThemeData(size: 24)),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    // Dark card language, matching the approved iPhone Map preview:
    // #1E2126 surface, #33373E outline, 16dp corners, no shadow.
    cardTheme: const CardThemeData(
      color: Color(0xFF1E2126),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: Color(0xFF33373E)),
      ),
    ),
  );
}

// ---- Destinations (6 tabs) ----
// Order: Map, Fares, Student, Friends, Communities, Account.
// Communities sits after Friends: the Community section moved out of
// the Friends tab into its own destination at the user's request.
class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = <_Destination>[
  _Destination('Map', Icons.map_outlined, Icons.map),
  _Destination('Fares', Icons.payments_outlined, Icons.payments),
  _Destination('Student', Icons.school_outlined, Icons.school),
  _Destination('Friends', Icons.people_outlined, Icons.people),
  _Destination('Communities', Icons.groups_outlined, Icons.groups),
  _Destination('Account', Icons.person_outlined, Icons.person),
];

class ByaheTayoApp extends StatefulWidget {
  const ByaheTayoApp({
    super.key,
    this.initialSidebarCollapsed = false,
    this.initialThemeMode = ThemeMode.system,
  });

  final bool initialSidebarCollapsed;
  final ThemeMode initialThemeMode;

  @override
  State<ByaheTayoApp> createState() => _ByaheTayoAppState();
}

class _ByaheTayoAppState extends State<ByaheTayoApp> {
  late ThemeMode _themeMode = widget.initialThemeMode;

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeModeKey, mode.name);
    } catch (_) {
      // Theme already switched in memory; a failed local save is not fatal.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ByaheTayo',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme(),
      darkTheme: _darkTheme(),
      themeMode: _themeMode,
      home: _HomeShell(
        initialSidebarCollapsed: widget.initialSidebarCollapsed,
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell({
    required this.initialSidebarCollapsed,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final bool initialSidebarCollapsed;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _index = 0;
  late bool _collapsed = widget.initialSidebarCollapsed;

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }

  Future<void> _toggleSidebar() async {
    setState(() => _collapsed = !_collapsed);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sidebarCollapsedKey, _collapsed);
    } catch (_) {
      // Sidebar already toggled in memory; a failed local save is not fatal.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Phones: bottom NavigationBar. Tablets / wide screens: collapsible
    // left sidebar. One codebase, both form factors.
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final body = IndexedStack(
      index: _index,
      children: [
        const MapTab(),
        const FaresTab(),
        StudentTheme(child: StudentTab(onViewOnMap: () => _select(0), onViewAccount: () => _select(5))),
        const FriendsTab(),
        CommunitiesTab(onViewOnMap: () => _select(0)),
        AccountTab(
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
        ),
      ],
    );

    if (wide) {
      return Scaffold(
        appBar: AppBar(title: Text(_destinations[_index].label)),
        // Top inset is handled by the AppBar; left/right/bottom insets
        // (gesture bar, cutouts) are respected here.
        body: SafeArea(
          top: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Sidebar(
                collapsed: _collapsed,
                selectedIndex: _index,
                onSelect: _select,
                onToggle: _toggleSidebar,
              ),
              // Expanded content stays responsive while the sidebar
              // animates; no overflow, no layout shift of the content.
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_destinations[_index].label)),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

/// Collapsible left sidebar for the wide layout.
///
/// Expanded (220dp): logo + "ByaheTayo" name at the top, then icon + label
/// rows. Collapsed (80dp): icons only, centered, labels hidden, selected
/// indicator preserved, every icon wrapped in a Tooltip. The chevron
/// toggle sits at the very top. Width animates (~225ms, easeInOut);
/// collapsing never touches the selected tab.
///
/// Layout switch: the expanded rows need ~144dp, so while the width
/// animates the sidebar shows the collapsed layout below 150dp and the
/// expanded layout at/above it — that way no row ever overflows
/// mid-animation (a plain ClipRect only clips paint, not layout).
class _Sidebar extends StatefulWidget {
  const _Sidebar({
    required this.collapsed,
    required this.selectedIndex,
    required this.onSelect,
    required this.onToggle,
  });

  final bool collapsed;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggle;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar>
    with SingleTickerProviderStateMixin {
  static const double _expandedWidth = 220;
  static const double _collapsedWidth = 80;
  static const double _layoutSwitchWidth = 150;

  late final AnimationController _controller;
  late final Animation<double> _width;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 225),
      value: widget.collapsed ? 1 : 0,
    );
    _width = Tween<double>(
      begin: _expandedWidth,
      end: _collapsedWidth,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant _Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapsed != oldWidget.collapsed) {
      if (widget.collapsed) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF94A3B8)
        : _textSecondary;
    return AnimatedBuilder(
      animation: _width,
      builder: (context, _) {
        final width = _width.value;
        final collapsedLayout = width < _layoutSwitchWidth;
        return SizedBox(
          key: const Key('sidebar-container'),
          width: width,
          child: ClipRect(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(right: BorderSide(color: scheme.outline)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (collapsedLayout)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        children: [
                          IconButton(
                            key: const Key('sidebar-toggle'),
                            icon: const Icon(Icons.chevron_right),
                            tooltip: 'Expand sidebar',
                            onPressed: widget.onToggle,
                          ),
                          const SizedBox(height: 8),
                          const _LogoMark(),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        children: [
                          const _LogoMark(),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'ByaheTayo',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            key: const Key('sidebar-toggle'),
                            icon: const Icon(Icons.chevron_left),
                            tooltip: 'Collapse sidebar',
                            onPressed: widget.onToggle,
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (int i = 0; i < _destinations.length; i++)
                            collapsedLayout
                                ? _collapsedItem(
                                    _destinations[i],
                                    i == widget.selectedIndex,
                                    muted,
                                    () => widget.onSelect(i),
                                  )
                                : _expandedItem(
                                    _destinations[i],
                                    i == widget.selectedIndex,
                                    muted,
                                    () => widget.onSelect(i),
                                  ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _expandedItem(
    _Destination destination,
    bool selected,
    Color muted,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        key: Key('sidebar-item-${destination.label}'),
        color: selected ? _primary : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 24,
                  color: selected ? Colors.white : muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    destination.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? Colors.white : muted,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _collapsedItem(
    _Destination destination,
    bool selected,
    Color muted,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Tooltip(
          message: destination.label,
          child: Material(
            key: Key('sidebar-item-${destination.label}'),
            color: selected ? _primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 24,
                  color: selected ? Colors.white : muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small branded mark: emerald rounded square with a bus icon.
class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.directions_bus, color: Colors.white, size: 22),
    );
  }
}
