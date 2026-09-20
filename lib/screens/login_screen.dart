import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_repository.dart';

/// Email + password login/register screen.
///
/// The app is gated by [AuthRepository.authState]: signing in/up here flips
/// the auth stream and [AppBootstrap] shows Home automatically. Real error
/// codes are mapped to short plain-English hints under the form.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthRepository auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _registering = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _friendly(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'That email address doesn’t look valid.';
        case 'user-not-found':
          return 'No account found with this email. Create one instead.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect password. Try again.';
        case 'email-already-in-use':
          return 'An account with this email already exists. Log in instead.';
        case 'weak-password':
          return 'Password is too weak — use at least 6 characters.';
        case 'operation-not-allowed':
        case 'admin-restricted-operation':
          return 'Email/Password sign-in is not enabled. Enable it in the '
              'Firebase console: Authentication → Sign-in method → Email/Password.';
        case 'network-request-failed':
        case 'too-many-requests':
          return 'Network problem. Check your connection and try again.';
        default:
          return e.message ?? e.code;
      }
    }
    return '$e';
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (_registering && _name.text.trim().isEmpty) {
      setState(() => _error = 'Pick a name so expenses can be attributed to you.');
      return;
    }
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter both email and password.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_registering) {
        await widget.auth.register(
          displayName: _name.text.trim(),
          email: email,
          password: password,
        );
      } else {
        await widget.auth.signIn(email: email, password: password);
      }
      // Success: the auth stream drives the rest of the app.
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.groups,
                      size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Split Chat',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _registering
                        ? 'Create an account with your email. Groups and '
                            'expenses are stored in the cloud.'
                        : 'Log in to see your expense groups. '
                            'Groups you join appear on Home.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 32),
                  if (_registering) ...[
                    TextField(
                      controller: _name,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        hintText: 'e.g. Jaswa',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_registering ? 'Create account' : 'Log in'),
                  ),
                  TextButton(
                    onPressed:
                        _busy ? null : () => setState(() {
                              _registering = !_registering;
                              _error = null;
                            }),
                    child: Text(_registering
                        ? 'Have an account? Log in'
                        : 'New here? Create an account'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}