// Rewards Center — the hub summary card + the shared redeem-all
// dialog flow. The center lives INSIDE the Student Hub (no new
// tab): this card is the hub entry point, and the full center
// (see rewards_screen.dart) is a pushed route, the same pattern as
// the Walking Goal and Sign-in details screens.
//
// HONEST STATES (no fake entries anywhere):
//   - Learning Activities, Achievements, and Referral Rewards have
//     no reward wiring yet, so they render as empty states, never
//     as invented rewards.
//   - Watch Ads & Earn Credits is BLOCKED: no AdMob SDK, no ad
//     units, no SSV server. No ad is shown or simulated, and no
//     credits are granted from any client callback. The section
//     states exactly what is missing and what a verified ad will
//     pay (0.50 credits) when the setup exists.
//   - The AI Scanner does not exist yet, so no scan can be started
//     from here; the card only shows the free-scan allowance
//     (3/day) and the paid-scan price (1 credit) that the gating
//     code will enforce once a scanner phase lands.
import 'package:flutter/material.dart';

import 'credits_repository.dart';
import 'ios_components.dart';
import 'minecraft_theme.dart';

/// Shared one-button redeem-all flow: confirmation dialog, then the
/// repository call, then a result dialog. [pointsBalance] is the
/// live ledger-derived points balance; the dialog converts ALL of
/// it (no manual input, no partial redemption). Returns without
/// doing anything when [onRedeem] is null (local-only mode).
Future<void> handleRedeem(
  BuildContext context, {
  required int pointsBalance,
  required Future<RedeemOutcome> Function()? onRedeem,
}) async {
  final redeem = onRedeem;
  if (redeem == null) {
    await showIosMessage(
      context: context,
      title: 'Redeem points',
      message: 'Sign in to redeem your points for credits.',
    );
    return;
  }
  if (pointsBalance <= 0) {
    await showIosMessage(
      context: context,
      title: 'Redeem points',
      message: 'You have 0 points to redeem. Earn points with the 7-Day '
          'Sign-in first.',
    );
    return;
  }
  final units = pointsToMinorUnits(pointsBalance);
  final confirmed = await showIosAlert<bool>(
    context: context,
    title: 'Redeem all points?',
    message: 'Convert ALL $pointsBalance points into '
        '${formatMinorUnits(units)} credits? '
        'You can redeem once per day.',
    actions: const [
      IosAlertAction<bool>('Cancel', value: false),
      IosAlertAction<bool>(
        'Redeem all',
        value: true,
        isDefault: true,
      ),
    ],
  );
  if (confirmed != true) return;
  final outcome = await redeem();
  if (!context.mounted) return;
  final message = switch (outcome.status) {
    RedeemStatus.redeemed =>
      'Converted ${outcome.pointsRedeemed} points into '
          '${formatMinorUnits(outcome.unitsCredited)} credits.',
    RedeemStatus.alreadyRedeemed =>
      'Already redeemed today. You can redeem again tomorrow.',
    RedeemStatus.zeroPoints =>
      'You have 0 points to redeem. Earn points with the 7-Day '
          'Sign-in first.',
    RedeemStatus.failed =>
      'Redemption failed. Nothing was changed — please try again.',
    RedeemStatus.unavailable =>
      'Sign in to redeem your points for credits.',
  };
  await showIosMessage(
    context: context,
    title: 'Redeem points',
    message: message,
  );
}

/// Hub summary card for the Rewards Center. Plain values in, so
/// widget tests can pump it without controllers.
class RewardsCenterCard extends StatelessWidget {
  const RewardsCenterCard({
    super.key,
    required this.pointsBalance,
    required this.creditsBalanceUnits,
    required this.scanFreeRemaining,
    required this.signedIn,
    required this.onRedeem,
    required this.onOpenFullCenter,
  });

  final int pointsBalance;
  final int creditsBalanceUnits;
  final int scanFreeRemaining;
  final bool signedIn;
  final Future<RedeemOutcome> Function()? onRedeem;
  final VoidCallback onOpenFullCenter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Minecraft restyle (Feature 2 — Student tab): blocky card,
    // gold star badge, Baloo 2 headings, emerald points / gold
    // credits. Every value is still the live controller value.
    return MinecraftCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const MinecraftIconBadge(
                icon: Icons.stars_rounded,
                backgroundColor: MinecraftColors.gold,
                iconColor: MinecraftColors.ink,
                size: 36,
                iconSize: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Rewards Center',
                  style: MinecraftText.title(color: scheme.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!signedIn) ...[
            Text(
              'Sign in to see your points, credits, and '
              'redemption history.',
              style: MinecraftText.body(color: scheme.onSurface),
            ),
          ] else ...[
            Text(
              '$pointsBalance points',
              style: MinecraftText.heading(
                color: MinecraftColors.emerald,
                fontSize: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${formatMinorUnits(creditsBalanceUnits)} credits',
              style: MinecraftText.title(
                color: isDark
                    ? MinecraftColors.gold
                    : MinecraftColors.goldDark,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'AI Scanner free scans left today: '
              '$scanFreeRemaining/$freeScansPerDay',
              style: MinecraftText.body(color: scheme.onSurface),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: minecraftBlockButtonStyle(),
              onPressed: () => handleRedeem(
                context,
                pointsBalance: pointsBalance,
                onRedeem: onRedeem,
              ),
              child: const Text('Redeem all points'),
            ),
            const SizedBox(height: 8),
            Text(
              'Watch Ads & Earn Credits is not available yet: '
              'ads need an AdMob setup and server verification '
              'first. No ad is shown here and no credits are '
              'granted for ads today.',
              style: MinecraftText.body(color: scheme.onSurface),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton(
            style: minecraftOutlinedButtonStyle(),
            onPressed: onOpenFullCenter,
            child: const Text('View full Rewards Center'),
          ),
        ],
      ),
    );
  }
}
