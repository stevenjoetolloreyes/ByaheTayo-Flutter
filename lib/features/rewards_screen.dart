// Rewards: the real account points balance, how points are actually
// earned, and an honest empty state for redemptions (there is no
// redemption catalog — nothing is invented or faked here).
import 'package:flutter/material.dart';

class RewardsScreen extends StatelessWidget {
  const RewardsScreen({
    super.key,
    required this.pointsBalance,
    required this.onOpenStudentHub,
  });

  /// The existing account wallet balance (not a new currency).
  final int pointsBalance;

  /// Opens the Student tab, where the 7-Day Sign-in lives.
  final VoidCallback onOpenStudentHub;

  @override
  Widget build(BuildContext context) {
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
                        'How to earn',
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
                        'Redemptions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'No redemptions available yet. There is no '
                        'redemption catalog in the app right now.',
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
