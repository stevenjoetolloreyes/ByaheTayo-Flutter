// Rewards Center (full screen) — points, credits, redeem-all,
// daily rewards, learning activities, achievements, referral
// rewards, watch-ads, redemption history, and rewarded-ads history.
//
// HONEST STATES — nothing here is invented:
//   - Points come from the real ledger-derived wallet; credits
//     from the real credits ledger (integer minor units).
//   - Learning Activities, Achievements, and Referral Rewards have
//     no reward wiring yet: their sections are empty states, not
//     sample rewards.
//   - The AI Scanner does not exist yet: its section shows the
//     free-scan allowance and the paid-scan price, but no scan can
//     be started from here.
//   - Watch Ads & Earn Credits shows real ads through the AdMob
//     SDK (Google test IDs until the real ad units are filled in
//     via the web edit). A completed ad still grants NOTHING:
//     verified crediting (0.50 credits per verified ad) needs the
//     SSV server, which does not exist yet, and no client callback
//     is ever treated as verified. The UI says so plainly.
//   - History rows show the spec's Source + ad fields (network,
//     reward reference, verification status); ad rows only ever
//     appear once a trusted server writes them.
import 'package:flutter/material.dart';

import 'ad_service.dart';
import 'credits_repository.dart';
import 'rewards_center.dart';

class RewardsScreen extends StatelessWidget {
  const RewardsScreen({
    super.key,
    required this.pointsBalance,
    required this.onOpenStudentHub,
    this.creditsBalanceUnits = 0,
    this.creditsTotalEarnedUnits = 0,
    this.creditsTotalSpentUnits = 0,
    this.creditsEntries = const [],
    this.adRewardEntries = const [],
    this.scanFreeRemaining = freeScansPerDay,
    this.dailyAdLimit = 5,
    this.onRedeem,
    this.adService,
  });

  /// The existing account wallet balance (not a new currency).
  final int pointsBalance;

  /// Opens the Student tab, where the 7-Day Sign-in lives.
  final VoidCallback onOpenStudentHub;

  /// Credits balances in minor units (1 credit = 100 units).
  final int creditsBalanceUnits;
  final int creditsTotalEarnedUnits;
  final int creditsTotalSpentUnits;

  /// Credits ledger entries (redemptions + scan charges).
  final List<CreditsTransaction> creditsEntries;

  /// Verified ad-reward entries (server-written only; empty until
  /// the SSV server exists).
  final List<CreditsTransaction> adRewardEntries;

  /// Free AI Scanner scans left today.
  final int scanFreeRemaining;

  /// Admin-configured daily rewarded-ad limit (display only until
  /// server enforcement exists).
  final int dailyAdLimit;

  /// One-button redeem-all (null in local-only mode).
  final Future<RedeemOutcome> Function()? onRedeem;

  /// Shared AdMob state (null in bare widget tests and in
  /// local-only mode, in which case the Watch Ads card keeps its
  /// honest no-ads notice and no ad is attempted).
  final AdService? adService;

  /// Rewarded-ad tap: shows one ad and reports the outcome
  /// honestly. No outcome here grants credits — not even
  /// `completed`, which is only a client-side callback, not
  /// verified crediting (that needs the SSV server).
  Future<void> _watchAd(BuildContext context) async {
    final service = adService;
    if (service == null) return;
    final result = await service.showRewardedAd();
    if (!context.mounted) return;
    final message = switch (result) {
      RewardedAdResult.completed =>
        'Ad completed. This completion is not verified crediting, '
            'so no credits were granted. Once the server '
            'verification is connected, one verified ad will earn '
            '0.50 credits.',
      RewardedAdResult.skipped => 'Ad not completed — no credits granted.',
      RewardedAdResult.failed =>
        'The ad could not be shown. No credits granted.',
      RewardedAdResult.noFill =>
        'No ad available right now. Try again later. '
            'No credits granted.',
    };
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Watch Ads & Earn Credits'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final redemptions =
        creditsEntries.where((e) => e.type == 'redemption').toList();
    final scanCharges =
        creditsEntries.where((e) => e.type == 'scan_charge').toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Rewards')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your points',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$pointsBalance points',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your credits',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${formatMinorUnits(creditsBalanceUnits)} credits',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total earned: '
                        '${formatMinorUnits(creditsTotalEarnedUnits)} '
                        'credits · Total spent: '
                        '${formatMinorUnits(creditsTotalSpentUnits)} '
                        'credits',
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '100 points = 1.00 credit. Credits pay for '
                        'AI Scanner scans and upcoming features.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => handleRedeem(
                          context,
                          pointsBalance: pointsBalance,
                          onRedeem: onRedeem,
                        ),
                        child: const Text('Redeem all points'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Daily Rewards',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Use the 7-Day Sign-in in the Student Hub: '
                        'Day 1–6 earn 10 points each, and Day 7 earns '
                        '50 points.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: onOpenStudentHub,
                        child: const Text('Open Student Hub'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AI Scanner',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Free scans left today: '
                        '$scanFreeRemaining/$freeScansPerDay',
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'After your free scans, each successful scan '
                        'costs 1 credit. Failed or cancelled scans '
                        'are never charged.',
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'The AI Scanner itself is not available yet, '
                        'so no scan can be started from here.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Learning Activities',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'No point rewards for learning activities '
                        'yet. Quizzes and notes stay local-only '
                        'until a reward path is built for them.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Achievements',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'No achievements yet. Achievements have not '
                        'been built, so nothing is listed here.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Referral Rewards',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'No referral rewards yet. Friend codes exist, '
                        'but no reward is wired to them.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Watch Ads & Earn Credits',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (adService == null)
                        const Text(
                          'Not available yet. Rewarded ads need an '
                          'AdMob setup (SDK, ad units, publisher '
                          'account) and a server that verifies '
                          'completed ads before any credits are '
                          'granted. No ad is shown here and no '
                          'credits are granted for ads today.',
                        )
                      else ...[
                        const Text(
                          'Watch a rewarded ad. A completed ad does '
                          'NOT grant credits yet: verified crediting '
                          'starts once the server verification is '
                          'connected, and no client-side completion '
                          'is ever treated as verified.',
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => _watchAd(context),
                          child: const Text('Watch ad'),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'When available, one verified ad earns '
                        '${formatMinorUnits(rewardedAdCreditUnits)} '
                        'credits. Daily limit set by admin: '
                        '$dailyAdLimit ads.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Redemption History',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (redemptions.isEmpty && scanCharges.isEmpty)
                        const Text('No redemptions yet.')
                      else ...[
                        for (final entry in redemptions)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(entry.description),
                            subtitle: Text(
                              'Source: ${entry.source} · ${entry.date}',
                            ),
                            trailing: Text(
                              '+${formatMinorUnits(entry.units)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        for (final entry in scanCharges)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(entry.description),
                            subtitle: Text(
                              'Source: ${entry.source} · ${entry.date}',
                            ),
                            trailing: Text(
                              formatMinorUnits(entry.units),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Rewarded Ads History',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (adRewardEntries.isEmpty)
                        const Text(
                          'No verified ad rewards yet. Ad rewards '
                          'only appear once server verification '
                          'exists.',
                        )
                      else
                        for (final entry in adRewardEntries)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(entry.description),
                            subtitle: Text(
                              'Network: ${entry.adNetwork ?? '—'} · '
                              'Ref: ${entry.adRewardReference ?? '—'} · '
                              'Status: '
                              '${entry.adVerificationStatus ?? '—'} · '
                              '${entry.date}',
                            ),
                            trailing: Text(
                              '+${formatMinorUnits(entry.units)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
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
  }
}
