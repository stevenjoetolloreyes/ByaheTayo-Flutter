// About EstudyanteGO screen — EstudyanteGO Flutter app.
//
// Shown INSIDE the Account tab (the shell's bottom navigation /
// sidebar stays visible) and returned to via [onBack], the same
// pattern as the Subscription Membership screen.
//
// The screen has three parts, all from Steven's Nov 7-8 picks:
//   1. An app stats graph — REAL live counts only, computed from the
//      app's actual data every time this screen opens (see
//      [computeAppStats]): routes (built-in + admin-added), hubs
//      (built-in), and cities & towns (bundled Philippines list).
//      No downloads, no user counts, no invented numbers.
//   2. Full-color section icons (the Account Actions rows use their
//      own colors in account_tab.dart; the graph bars here do the
//      same — one color per stat, not the green-tinted monochrome).
//   3. Lots of text: substantial About copy describing what the app
//      does. Descriptive copy only — no invented statistics and no
//      features the app does not have (the queued Full Development
//      Update — attendance, classes, tasks, budgeting — is NOT
//      described here because it is not built yet).
//
// The Privacy Policy is deliberately NOT part of this screen
// (Steven, Nov 8: "Hindi, hiwalay lang yung Privacy Policy") — it
// stays as its own separate entry on the Account tab.
import 'package:flutter/material.dart';

import 'custom_routes.dart';
import 'minecraft_theme.dart';
import 'fares_tab.dart';
import 'philippine_places.dart';

/// Live app stats, computed from the app's real data sources.
///
/// Every count comes from a named in-app source — nothing is
/// hardcoded and nothing is invented:
/// * [routes] — [popularRoutes] (built-in routes) plus the
///   admin-added custom routes loaded from [CustomRouteRepository].
/// * [hubs] — [hubs] (the built-in hub & terminal list).
/// * [cities] — [philippinePlaces] (the bundled Philippines list).
class AppStats {
  const AppStats({
    required this.routes,
    required this.hubs,
    required this.cities,
  });

  final int routes;
  final int hubs;
  final int cities;
}

/// Computes [AppStats] from the live data sources. [customRouteCount]
/// is the number of admin-added custom routes currently stored
/// (0 when the repository is unavailable or empty).
AppStats computeAppStats({required int customRouteCount}) => AppStats(
      routes: popularRoutes.length + customRouteCount,
      hubs: hubs.length,
      cities: philippinePlaces.length,
    );

/// About EstudyanteGO screen.
///
/// [customRouteRepository] is optional: when null, the graph counts
/// the built-in routes only; when provided, the admin-added custom
/// routes are loaded (async, with a progress indicator until they
/// arrive) and added to the routes count.
class AboutEstudyanteGOScreen extends StatefulWidget {
  const AboutEstudyanteGOScreen({
    super.key,
    required this.onBack,
    this.customRouteRepository,
  });

  /// Return to the Account page content.
  final VoidCallback onBack;

  final CustomRouteRepository? customRouteRepository;

  @override
  State<AboutEstudyanteGOScreen> createState() =>
      _AboutEstudyanteGOScreenState();
}

class _AboutEstudyanteGOScreenState extends State<AboutEstudyanteGOScreen> {
  /// Admin-added custom route count, or null while it is loading.
  int? _customRouteCount;

  @override
  void initState() {
    super.initState();
    _loadCustomRouteCount();
  }

  Future<void> _loadCustomRouteCount() async {
    final repo = widget.customRouteRepository;
    if (repo == null) {
      if (mounted) setState(() => _customRouteCount = 0);
      return;
    }
    final routes = await repo.loadAll();
    if (mounted) setState(() => _customRouteCount = routes.length);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final stats = _customRouteCount == null
        ? null
        : computeAppStats(customRouteCount: _customRouteCount!);
    return SingleChildScrollView(
      key: const Key('about-screen-scroll-view'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back to Account',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            _brandBlock(dark, onSurface, muted),
            const SizedBox(height: 24),
            _statsCard(stats, dark, onSurface, muted),
            const SizedBox(height: 24),
            _textSection(
              'What is EstudyanteGO?',
              'EstudyanteGO is a student companion for getting around '
              'Northern Philippines. It puts your commute, your fares, '
              'and your study tools in one place — built for students '
              'who ride the bus or jeepney to school every day.',
              onSurface,
              muted,
            ),
            const SizedBox(height: 24),
            _textSection(
              'Fares',
              'Check the fare before you ride. The app computes '
              'LTFRB-based fare estimates for jeepneys and buses, and '
              'marks verified operator fares where they are known. '
              'Fares shown are estimates unless marked as a verified '
              'fare. An admin sets the final fares for each route, '
              'including the discounted fare for students, persons '
              'with disabilities, and senior citizens.',
              onSurface,
              muted,
            ),
            const SizedBox(height: 24),
            _textSection(
              'Routes & map',
              'See your route drawn on the map, with the bus stops '
              'along the way. Pick a starting point and a destination '
              'from anywhere in the Philippines — from the built-in '
              'hubs and terminals to the bundled list of cities and '
              'towns — and jump from a fare straight to its direction '
              'on the map.',
              onSurface,
              muted,
            ),
            const SizedBox(height: 24),
            _textSection(
              'Study tools',
              'Grades, files, notes, and review quizzes live in the '
              'Study tab. Keep your subjects and grades in one place, '
              'store your study files, write notes, and turn your '
              'notes into practice quizzes to review before an exam.',
              onSurface,
              muted,
            ),
            const SizedBox(height: 24),
            _textSection(
              'Communities',
              'Students share posts in Communities — announcements, '
              'questions, and updates from your schoolmates. Every '
              'shared post is reviewed by an admin before it goes '
              'live, so what you see has been approved, not just '
              'posted.',
              onSurface,
              muted,
            ),
            const SizedBox(height: 24),
            _textSection(
              'Points',
              'Daily sign-ins earn you points, tracked in your wallet '
              'on the Account tab. Your points balance, credits, and '
              'transaction history all live there too.',
              onSurface,
              muted,
            ),
            const SizedBox(height: 24),
            _textSection(
              'Made by a student, for students',
              'EstudyanteGO is built by a student developer in the '
              'Philippines, for students riding to school across the '
              'North. If something looks wrong — a fare, a stop, a '
              'route — tell the admin, and it gets fixed.',
              onSurface,
              muted,
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 20, 0, 5),
              child: Text(
                'ESTUDYANTEGO · VERSION 1.0.0',
                textAlign: TextAlign.center,
                style: MinecraftText.pixel(color: muted, fontSize: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Brand block: green E tile, wordmark, tagline (the same Tagalog
  /// tagline as the splash screen), and the version.
  Widget _brandBlock(bool dark, Color onSurface, Color muted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: MinecraftColors.grassGreen,
            borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
            border: MinecraftShapes.blockBorder,
            boxShadow: const [MinecraftShapes.cardShadow],
          ),
          alignment: Alignment.center,
          child: Text(
            'E',
            style: MinecraftText.pixel(color: Colors.white, fontSize: 28),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'EstudyanteGO',
          style: MinecraftText.heading(color: onSurface, fontSize: 26),
        ),
        const SizedBox(height: 4),
        Text(
          'Kasama mo sa araw-araw na eskwela',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: muted),
        ),
        const SizedBox(height: 8),
        Text(
          'Version 1.0.0 · com.estudyantego.app',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: muted),
        ),
      ],
    );
  }

  /// App stats graph card. The bars are drawn from [stats] — live
  /// counts, never hardcoded. While the custom-route count is still
  /// loading, a progress indicator stands in for the graph so no
  /// partial number is ever shown.
  Widget _statsCard(AppStats? stats, bool dark, Color onSurface, Color muted) {
    return MinecraftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'App stats',
              style: MinecraftText.title(color: onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              'Live counts from the app\u2019s data — updated every '
              'time this screen opens.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 16),
            if (stats == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              _statBar(
                key: const Key('about-stat-routes'),
                label: 'Routes',
                count: stats.routes,
                maxCount: _maxCount(stats),
                color: MinecraftColors.grassGreen,
              ),
              const SizedBox(height: 12),
              _statBar(
                key: const Key('about-stat-hubs'),
                label: 'Hubs',
                count: stats.hubs,
                maxCount: _maxCount(stats),
                color: MinecraftColors.skyBlue,
              ),
              const SizedBox(height: 12),
              _statBar(
                key: const Key('about-stat-cities'),
                label: 'Cities & towns',
                count: stats.cities,
                maxCount: _maxCount(stats),
                color: MinecraftColors.goldDark,
              ),
              const SizedBox(height: 16),
              Text(
                'Routes — built-in routes plus routes added by an '
                'admin. Hubs — built-in hubs and terminals. Cities & '
                'towns — places in the bundled Philippines list.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ],
        ),
    );
  }

  int _maxCount(AppStats stats) =>
      [stats.routes, stats.hubs, stats.cities].reduce(
        (a, b) => a > b ? a : b,
      );

  /// One horizontal bar: label, a bar whose width is proportional
  /// to [count] / [maxCount] (linear scale, so the bars stay
  /// comparable), and the count itself. The count is always printed
  /// — the bar is a picture of the number, never a replacement for
  /// it.
  Widget _statBar({
    required Key key,
    required String label,
    required int count,
    required int maxCount,
    required Color color,
  }) {
    final fraction =
        maxCount <= 0 ? 0.0 : (count / maxCount).clamp(0.02, 1.0);
    return Row(
      key: key,
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Container(
            height: 22,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              child: Container(
                height: 22,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 40,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  /// One About text section: bold heading over a paragraph.
  Widget _textSection(
    String heading,
    String body,
    Color onSurface,
    Color muted,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: MinecraftText.title(color: onSurface),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: MinecraftText.body(color: muted, fontSize: 13),
        ),
      ],
    );
  }
}
