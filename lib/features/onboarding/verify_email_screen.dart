// Email verification step after registration or sign-in with an
// unverified email.
//
// Sends the real Firebase verification email, then re-checks via
// [AuthService.reloadUser]. The user is never trapped here: "Use a
// different account" signs out and returns to sign-in.
import 'package:flutter/material.dart';
import '../top_popup.dart';

import '../app_layout.dart';
import 'auth_service.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    required this.service,
    required this.user,
    required this.onVerified,
    required this.onUseDifferentAccount,
  });

  final AuthService service;
  final AuthUser user;
  final ValueChanged<AuthUser> onVerified;
  final VoidCallback onUseDifferentAccount;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _sending = false;
  bool _checking = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await widget.service.sendEmailVerification();
      if (!mounted) return;
      TopPopup.show(context, message: 'Verification email sent. Check your inbox.');
    } on AuthException catch (e) {
      if (mounted) {
        TopPopup.show(context, message: e.message);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final fresh = await widget.service.reloadUser();
      if (!mounted) return;
      if (fresh != null && fresh.emailVerified) {
        widget.onVerified(fresh);
      } else {
        TopPopup.show(context, message: 'Not verified yet. Open the link in your email, then ' 'check again.',);
      }
    } on AuthException catch (e) {
      if (mounted) {
        TopPopup.show(context, message: e.message);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _differentAccount() async {
    try {
      await widget.service.signOut();
    } catch (_) {
      // Still return to sign-in: the local gate state is what matters.
    }
    if (mounted) widget.onUseDifferentAccount();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify your email')),
      body: SafeArea(
        child: Padding(
          padding: AppLayout.pagePaddingLarge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.s16),
              Container(
                width: AppLayout.emptyIllustrationSize,
                height: AppLayout.emptyIllustrationSize,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppLayout.emptyIllustrationRadius),
                ),
                child: Icon(
                  Icons.mark_email_unread_outlined,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.s16),
              const Text(
                'Check your email',
                style: AppText.titleMedium,
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                'We sent a verification link to ${widget.user.email}. '
                'Open it, then come back here and check again.',
                style: AppText.label.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _sending ? null : _send,
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send verification email'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _checking ? null : _check,
                child: const Text("I've verified — check again"),
              ),
              const Spacer(),
              TextButton(
                onPressed: _differentAccount,
                child: const Text('Use a different account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
