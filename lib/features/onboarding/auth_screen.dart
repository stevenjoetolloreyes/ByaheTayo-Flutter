// Sign-in / create-account screen, driven by [AuthService].
//
// Modes switch in place (no separate routes). Forgot password is a
// dialog that sends the Firebase reset email. When the service reports
// Firebase as not configured, the form shows a clear banner and the
// submit buttons stay disabled — the app never crashes and never fakes
// a sign-in.
import 'package:flutter/material.dart';

import 'auth_service.dart';

enum AuthMode { signIn, createAccount }

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.service,
    this.initialMode = AuthMode.signIn,
    required this.onSignedIn,
    required this.onAccountCreated,
  });

  final AuthService service;
  final AuthMode initialMode;
  final ValueChanged<AuthUser> onSignedIn;
  final ValueChanged<AuthUser> onAccountCreated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late AuthMode _mode = widget.initialMode;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _loading = false;
  String? _error;

  bool get _configured => widget.service.isConfigured;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String? _validate() {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      return 'Enter a valid email address.';
    }
    if (_passwordController.text.isEmpty) {
      return 'Enter your password.';
    }
    if (_mode == AuthMode.createAccount) {
      if (_nameController.text.trim().isEmpty) {
        return 'Enter your full name.';
      }
      if (_passwordController.text.length < 6) {
        return 'Password must be at least 6 characters.';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      if (_mode == AuthMode.signIn) {
        final user =
            await widget.service.signIn(email: email, password: password);
        if (!mounted) return;
        widget.onSignedIn(user);
      } else {
        final user = await widget.service.createAccount(
          email: email,
          password: password,
          displayName: _nameController.text.trim(),
        );
        if (!mounted) return;
        widget.onAccountCreated(user);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final emailController = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forgot password?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your email and we will send you a password reset link.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send link'),
          ),
        ],
      ),
    );
    if (send != true || !mounted) return;
    final email = emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid email address.')),
        );
      }
      return;
    }
    try {
      await widget.service.sendPasswordReset(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset link sent. Check your email.'),
        ),
      );
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = _mode == AuthMode.createAccount;
    return Scaffold(
      appBar: AppBar(title: Text(isCreate ? 'Create account' : 'Sign in')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.directions_bus,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isCreate ? 'Welcome to EstudyanteGO' : 'Welcome back',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isCreate
                    ? 'Create an account to save your profile and settings.'
                    : 'Sign in to continue to EstudyanteGO.',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),
              if (!_configured)
                Card(
                  color: Theme.of(context)
                      .colorScheme
                      .errorContainer
                      .withValues(alpha: 0.5),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Firebase is not configured yet, so sign-in is '
                            'unavailable in this build. Add '
                            'google-services.json to enable it.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!_configured) const SizedBox(height: 16),
              if (isCreate) ...[
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              if (!isCreate) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _configured ? _forgotPassword : null,
                    child: const Text('Forgot password?'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: (_loading || !_configured) ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isCreate ? 'Create account' : 'Sign in'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => setState(() {
                          _mode = isCreate
                              ? AuthMode.signIn
                              : AuthMode.createAccount;
                          _error = null;
                        }),
                child: Text(
                  isCreate
                      ? 'Already have an account? Sign in'
                      : "Don't have an account? Create one",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
