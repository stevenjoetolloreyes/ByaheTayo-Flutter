// Subscription Membership flow — EstudyanteGO Flutter app.
//
// UI + navigation only. Plans are ADMIN-ASSIGNED: the admin sets the
// `plan` field on the user's Firestore `student_profiles` document
// and the app never writes it, so there is NO payment provider here
// and Subscribe Now must never charge, verify, or activate anything.
// Tapping Subscribe on Standard or Pro shows an honest sheet saying
// plans are assigned by the admin (see [_showCheckoutSheet]) and
// records nothing. Plan selection is transient UI state inside this
// flow, not a purchased membership — the screen always shows the
// user's real current plan (from the local profile, passed in as
// [SubscriptionMembershipScreen.currentPlan]), never the selection.
//
// Prices are the approved figures: Free ₱0; Standard ₱99/month or
// ₱950/year; Pro ₱299/month or ₱2,870/year (yearly = 20% off).
// Storage limits are the approved spec (Free 2 GB, Standard 12 GB,
// Pro 30 GB), shown on the plan cards; the Files add flow enforces
// the real plan's limit (see study_tab.dart).
import 'package:flutter/material.dart';

import 'app_layout.dart';
import 'minecraft_theme.dart';

/// Billing period for a subscription plan.
enum SubscriptionBilling { monthly, yearly }

/// The three membership tiers.
enum SubscriptionPlanId { free, standard, pro }

/// One membership tier with its approved prices and benefits.
class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.benefits,
    required this.storageGB,
    required this.icon,
    required this.iconColor,
  });

  final SubscriptionPlanId id;
  final String name;

  /// Monthly price in pesos (0 for Free).
  final int monthlyPrice;

  /// Yearly price in pesos (0 for Free).
  final int yearlyPrice;

  final List<String> benefits;

  /// Included file storage in GB (approved spec: Free 2, Standard 12,
  /// Pro 30). This is the single source of truth for storage limits:
  /// [subscriptionStorageLimitBytes] reads it, and the Files add flow
  /// enforces it against the user's real plan.
  final int storageGB;

  /// Included file storage in bytes, derived from [storageGB] (1 GB =
  /// 1024^3 bytes). This is the single source of truth for storage
  /// limits: [subscriptionStorageLimitBytes] reads it, never a
  /// hardcoded byte count.
  int get storageBytes => storageGB * 1024 * 1024 * 1024;

  /// Display line for the plan card, e.g. "2 GB storage".
  String get storageLabel => '$storageGB GB storage';

  /// Leading icon for the plan card. Pro uses the widget-drawn crown
  /// ([isCrown]) instead of a glyph.
  final IconData icon;
  final Color iconColor;

  bool get isFree => id == SubscriptionPlanId.free;
  bool get isCrown => id == SubscriptionPlanId.pro;

  int priceFor(SubscriptionBilling billing) =>
      billing == SubscriptionBilling.monthly ? monthlyPrice : yearlyPrice;

  /// Display price for the selected billing period.
  String priceLabel(SubscriptionBilling billing) {
    if (isFree) return '₱0 / forever';
    if (billing == SubscriptionBilling.monthly) {
      return '₱${_formatAmount(monthlyPrice)} / month';
    }
    return '₱${_formatAmount(yearlyPrice)} / year';
  }

  /// Monthly-equivalent note for yearly billing (e.g. ≈ ₱79/mo).
  String? monthlyEquivalentNote(SubscriptionBilling billing) {
    if (isFree || billing == SubscriptionBilling.monthly) return null;
    return '≈ ₱${(yearlyPrice / 12).round()}/mo';
  }

}

const List<SubscriptionPlan> subscriptionPlans = [
  SubscriptionPlan(
    id: SubscriptionPlanId.free,
    name: 'Free',
    monthlyPrice: 0,
    yearlyPrice: 0,
    benefits: ['Basic features', 'With advertisements'],
    storageGB: 2,
    icon: Icons.eco_rounded,
    iconColor: MinecraftColors.grassGreen,
  ),
  SubscriptionPlan(
    id: SubscriptionPlanId.standard,
    name: 'Standard',
    monthlyPrice: 99,
    yearlyPrice: 950,
    benefits: ['All Free features', 'No advertisements'],
    storageGB: 12,
    icon: Icons.bolt_rounded,
    iconColor: MinecraftColors.goldDark,
  ),
  SubscriptionPlan(
    id: SubscriptionPlanId.pro,
    name: 'Pro',
    monthlyPrice: 299,
    yearlyPrice: 2870,
    benefits: [
      'All Standard features',
      'No advertisements',
      'Priority Support',
      'Publishing in Communities',
    ],
    storageGB: 30,
    icon: Icons.diamond_rounded,
    iconColor: MinecraftColors.gold,
  ),
];

/// Parses a raw plan value (e.g. the `plan` field of a Firestore
/// `student_profiles` document, set by the admin in the Firebase
/// Console) into a [SubscriptionPlanId]. Matching is case-insensitive
/// and ignores surrounding whitespace. Anything missing, non-string,
/// or unknown falls back to [SubscriptionPlanId.free] — a plan is
/// never invented for a user.
SubscriptionPlanId parseSubscriptionPlanId(Object? raw) {
  if (raw is! String) return SubscriptionPlanId.free;
  switch (raw.trim().toLowerCase()) {
    case 'free':
      return SubscriptionPlanId.free;
    case 'standard':
      return SubscriptionPlanId.standard;
    case 'pro':
      return SubscriptionPlanId.pro;
    default:
      return SubscriptionPlanId.free;
  }
}

/// The [SubscriptionPlan] for [id]. Always found: the three plans in
/// [subscriptionPlans] cover every [SubscriptionPlanId].
SubscriptionPlan subscriptionPlanForId(SubscriptionPlanId id) =>
    subscriptionPlans.firstWhere((plan) => plan.id == id);

/// Shared source of truth for the Files storage limit: the included
/// storage for [id] in bytes, read from the plan constants in
/// [subscriptionPlans] (Free 2 GB, Standard 12 GB, Pro 30 GB).
/// No byte count is hardcoded here or anywhere else.
int subscriptionStorageLimitBytes(SubscriptionPlanId id) =>
    subscriptionPlanForId(id).storageBytes;

/// Thousands separator for peso amounts (2870 → 2,870).
String _formatAmount(int value) {
  if (value < 1000) return '$value';
  return '${value ~/ 1000},${(value % 1000).toString().padLeft(3, '0')}';
}

// Deep emerald is LOCKED by student_dark_mode_test.dart (the plan
// price must stay #14532D in Light Mode) — do not re-point it.
// The other accents below are Minecraft palette tokens.
const Color _deepEmerald = Color(0xFF14532D);
const Color _brightGreen = MinecraftColors.grassGreen;
const Color _lightGreen = Color(0xFFD9F7C4);
const Color _gold = MinecraftColors.gold;

// Dark-mode-readable emerald (same value as the app dark theme's
// primary). Deep emerald #14532D as text on a dark card is
// unreadable, so dark-mode price text uses this instead — light
// mode keeps _deepEmerald exactly.
const Color _lightEmerald = MinecraftColors.darkAccent;

/// Gold crown drawn with widgets (no image asset, no emoji).
class CrownIcon extends StatelessWidget {
  const CrownIcon({super.key, this.size = 48, this.color = _gold});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CrownPainter(color)),
    );
  }
}

class _CrownPainter extends CustomPainter {
  _CrownPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, h * 0.82)
      ..lineTo(0, h * 0.32)
      ..lineTo(w * 0.22, h * 0.58)
      ..lineTo(w * 0.5, h * 0.12)
      ..lineTo(w * 0.78, h * 0.58)
      ..lineTo(w, h * 0.32)
      ..lineTo(w, h * 0.82)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawRect(Rect.fromLTWH(0, h * 0.82, w, h * 0.18), paint);
  }

  @override
  bool shouldRepaint(_CrownPainter oldDelegate) => oldDelegate.color != color;
}

/// Subscription Membership screen.
///
/// Shown INSIDE the Account tab (the shell's bottom navigation /
/// sidebar stays visible) and returned to via [onBack]. Selecting a
/// plan updates the action button; the button opens the plan details
/// screen for the selected plan. The 'Current Plan' mark and the
/// header line always come from [currentPlan] (the user's real,
/// admin-assigned plan), never from the transient selection.
class SubscriptionMembershipScreen extends StatefulWidget {
  const SubscriptionMembershipScreen({
    super.key,
    required this.onBack,
    this.currentPlan = SubscriptionPlanId.free,
  });

  /// Return to the Account page content.
  final VoidCallback onBack;

  /// The user's REAL current plan, from the local profile (a cached
  /// copy of the admin-assigned `plan` on the Firestore
  /// `student_profiles` doc). Defaults to Free when no profile is
  /// loaded; a plan is never invented.
  final SubscriptionPlanId currentPlan;

  @override
  State<SubscriptionMembershipScreen> createState() =>
      _SubscriptionMembershipScreenState();
}

class _SubscriptionMembershipScreenState
    extends State<SubscriptionMembershipScreen> {
  SubscriptionBilling _billing = SubscriptionBilling.monthly;
  SubscriptionPlan _selected =
      subscriptionPlans[2]; // Pro pre-selected, per the approved preview.

  void _openDetails() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubscriptionPlanDetailsScreen(
          plan: _selected,
          billing: _billing,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // When the selected plan IS the user's current plan there is
    // nothing to upgrade to — the button stays disabled, exactly
    // as it does for Free (the default current plan).
    final isCurrentPlan = _selected.id == widget.currentPlan;
    final actionLabel = isCurrentPlan || _selected.isFree
        ? 'Current Plan'
        : 'Upgrade to ${_selected.name}';
    return SingleChildScrollView(
      key: const Key('subscription-membership-scroll-view'),
      child: Padding(
        padding: AppLayout.pagePaddingTab,
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
            _banner(),
            const SizedBox(height: AppLayout.cardGap),
            _currentPlanLine(),
            const SizedBox(height: AppLayout.cardGap),
            _billingSelector(),
            const SizedBox(height: AppLayout.cardGap),
            for (final plan in subscriptionPlans) ...[
              _planCard(plan),
              const SizedBox(height: AppLayout.cardGap),
            ],
            ElevatedButton(
              key: const Key('membership-action-button'),
              style: minecraftBlockButtonStyle(),
              onPressed:
                  isCurrentPlan || _selected.isFree ? null : _openDetails,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    actionLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!_selected.isFree) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded, size: 20),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Header line stating the user's real current plan and its
  /// storage limit. Read from [widget.currentPlan] — never from
  /// the transient [_selected] state, so tapping another card
  /// never moves the 'current plan' mark.
  Widget _currentPlanLine() {
    final current = subscriptionPlanForId(widget.currentPlan);
    return Text(
      'Current plan: ${current.name} — ${current.storageLabel}',
      key: const Key('current-plan-line'),
      style: AppText.label,
    );
  }

  Widget _banner() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_deepEmerald, _brightGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius:
            BorderRadius.all(Radius.circular(AppLayout.cardRadius)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _PremiumBadge(),
                  const SizedBox(height: 8),
                  Text(
                    'Upgrade Your Experience',
                    style: MinecraftText.heading(
                      color: Colors.white,
                      fontSize: 22,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Choose a plan that fits your needs and enjoy more '
                    'features.',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const CrownIcon(size: 72),
          ],
        ),
      ),
    );
  }

  Widget _billingSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Expanded(
            child: _billingOption(
              key: const Key('billing-monthly'),
              label: 'Monthly',
              billing: SubscriptionBilling.monthly,
            ),
          ),
          Expanded(
            child: _billingOption(
              key: const Key('billing-yearly'),
              label: 'Yearly',
              billing: SubscriptionBilling.yearly,
              badge: 'Save up to 20%',
            ),
          ),
        ],
      ),
    );
  }

  Widget _billingOption({
    required Key key,
    required String label,
    required SubscriptionBilling billing,
    String? badge,
  }) {
    final selected = _billing == billing;
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _billing = billing),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? _deepEmerald : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        // Badge sits under the label (not beside it) so the segment
        // never overflows on narrow phones.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(height: 2),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _gold,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: _deepEmerald,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _planCard(SubscriptionPlan plan) {
    final selected = _selected.id == plan.id;
    final equivalent = plan.monthlyEquivalentNote(_billing);
    return MinecraftCard(
      key: Key('plan-card-${plan.id.name}'),
      onTap: () => setState(() => _selected = plan),
      padding: AppLayout.cardPadding,
      child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: plan.iconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: plan.isCrown
                        ? const Center(child: CrownIcon(size: 28))
                        : Icon(plan.icon, color: plan.iconColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(plan.name, style: MinecraftText.title()),
                        Text(
                          plan.priceLabel(_billing),
                          style: MinecraftText.heading(
                            // Dark Mode (Nov 2 polish): deep emerald
                            // on a dark card was the reported
                            // low-contrast bug — light emerald reads
                            // clearly there. Light mode unchanged.
                            color: Theme.of(context).brightness ==
                                    Brightness.dark
                                ? _lightEmerald
                                : _deepEmerald,
                            fontSize: 16,
                          ),
                        ),
                        if (equivalent != null)
                          Text(
                            equivalent,
                            style: AppText.label,
                          ),
                      ],
                    ),
                  ),
                  // 'Current Plan' marks the user's REAL current
                  // plan (from the local profile), not the transient
                  // selection and not always Free.
                  if (plan.id == widget.currentPlan)
                    const _Pill(
                      label: 'Current Plan',
                      background: _lightGreen,
                      foreground: _deepEmerald,
                    ),
                  if (plan.id == SubscriptionPlanId.pro)
                    const _Pill(
                      label: 'Recommended',
                      background: _deepEmerald,
                      foreground: Colors.white,
                    ),
                  const SizedBox(width: 8),
                  _RadioDot(selected: selected),
                ],
              ),
              const SizedBox(height: 12),
              for (final benefit in plan.benefits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 20,
                        color: _brightGreen,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(benefit)),
                    ],
                  ),
                ),
              // Storage line: states the approved per-plan storage
              // spec. The Files add flow enforces this limit against
              // the user's real plan (see study_tab.dart).
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: _brightGreen,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(plan.storageLabel)),
                  ],
                ),
              ),
            ],
          ),
    );
  }
}

class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
      ),
      child: const Text(
        'Byahe Tayo Premium',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? _brightGreen : Colors.transparent,
        border: Border.all(
          color: selected ? _brightGreen : Colors.grey,
          width: 2,
        ),
      ),
      child: selected
          ? const Center(
              child: SizedBox(
                width: 10,
                height: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

/// Plan Details screen, pushed on top of the Membership screen.
///
/// This is a full route, so the shell's bottom navigation / sidebar is
/// NOT visible here — matching the approved preview. [plan] and
/// [billing] come from the Membership selection.
class SubscriptionPlanDetailsScreen extends StatelessWidget {
  const SubscriptionPlanDetailsScreen({
    super.key,
    required this.plan,
    required this.billing,
  });

  final SubscriptionPlan plan;
  final SubscriptionBilling billing;

  String get _billingLabel =>
      billing == SubscriptionBilling.monthly ? 'Monthly' : 'Yearly';

  String get _subtitle {
    switch (plan.id) {
      case SubscriptionPlanId.free:
        return 'The basics to get you started.';
      case SubscriptionPlanId.standard:
        return 'More features with no advertisements.';
      case SubscriptionPlanId.pro:
        return 'Get the full Byahe Tayo experience with exclusive '
            'features.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${plan.name} Plan')),
      body: SingleChildScrollView(
        key: const Key('subscription-details-scroll-view'),
        child: Padding(
          padding: AppLayout.pagePaddingTab,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _banner(),
              const SizedBox(height: AppLayout.cardGap),
              Text('Plan Summary', style: AppText.cardTitle),
              const SizedBox(height: 8),
              MinecraftCard(
                padding: EdgeInsets.zero,
                // Custom rows, not ListTiles: the Renewal value
                // ("Auto-renew (cancel anytime)") is too wide for a
                // ListTile trailing slot on narrow phones and trips
                // a layout assertion. Rows wrap instead of asserting.
                child: Column(
                  children: [
                    _summaryRow(
                      Icons.calendar_month_rounded,
                      'Billing',
                      _billingLabel,
                    ),
                    const Divider(height: 1),
                    _summaryRow(
                      Icons.payments_rounded,
                      'Price',
                      plan.priceLabel(billing),
                    ),
                    const Divider(height: 1),
                    _summaryRow(
                      Icons.autorenew_rounded,
                      'Renewal',
                      plan.isFree
                          ? 'No renewal'
                          : 'Auto-renew (cancel anytime)',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppLayout.cardGap),
              Text('Plan Benefits', style: AppText.cardTitle),
              const SizedBox(height: 8),
              MinecraftCard(
                padding: AppLayout.cardPadding,
                child: Column(
                    children: [
                      for (final benefit in plan.benefits)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 24,
                                color: _brightGreen,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  benefit,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ),
              const SizedBox(height: AppLayout.cardGap),
              ElevatedButton(
                key: const Key('subscribe-now-button'),
                style: minecraftBlockButtonStyle(),
                onPressed: plan.isFree
                    ? null
                    : () => _showCheckoutSheet(context),
                child: Text(
                  plan.isFree ? 'Current Plan' : 'Subscribe Now',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shield_rounded,
                    size: 20,
                    color: _brightGreen,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Secure Payment',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Your transaction is safe and encrypted.',
                textAlign: TextAlign.center,
                // Dark Mode (Nov 2 polish): secondary info uses the
                // user's #B0B8B5 token instead of grey. Light mode
                // keeps the exact grey it had.
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFFB0B8B5)
                      : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_deepEmerald, _brightGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius:
            BorderRadius.all(Radius.circular(AppLayout.cardRadius)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _lightGreen,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(child: CrownIcon(size: 32)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${plan.name} Plan',
                    style: MinecraftText.heading(
                      color: Colors.white,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _subtitle,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.directions_bus_rounded,
                size: 36,
                color: _brightGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: _brightGreen),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  /// Honest stop: plans are ADMIN-ASSIGNED, so there is nothing to
  /// confirm here. The sheet shows what the plan would be and tells
  /// the user to ask the admin to upgrade. Nothing is recorded,
  /// no payment is taken, and the plan never changes.
  void _showCheckoutSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Plan upgrade',
                style: MinecraftText.heading(fontSize: 20),
              ),
              const SizedBox(height: 16),
              _sheetRow('Plan', plan.name),
              _sheetRow('Billing', _billingLabel),
              _sheetRow('Price', plan.priceLabel(billing)),
              _sheetRow(
                'Renewal',
                plan.isFree ? 'No renewal' : 'Auto-renew (cancel anytime)',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _lightGreen,
                  borderRadius:
                      BorderRadius.circular(AppLayout.cardRadius),
                ),
                // Dark Mode (Nov 2 polish): this note sits on a
                // light-green tile, so inherited dark-mode text
                // (white) would be unreadable on it — pin it to
                // deep emerald in dark mode. Light mode inherits
                // exactly as before.
                child: Text(
                  'Plans are assigned by the admin. Ask the admin to '
                  'upgrade your plan to ${plan.name}. Your plan '
                  'hasn\'t changed.',
                  style: TextStyle(
                    color: Theme.of(sheetContext).brightness ==
                            Brightness.dark
                        ? _deepEmerald
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sheetRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
