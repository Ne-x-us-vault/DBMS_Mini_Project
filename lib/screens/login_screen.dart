import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_repository.dart';
import '../theme/app_theme.dart';

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
    if (e is UsernameTakenException) {
      return 'That name is already taken. Try another one.';
    }
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
                  _Hero(registering: _registering),
                  const SizedBox(height: 16),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_registering) ...[
                            TextField(
                              controller: _name,
                              enabled: !_busy,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Your name',
                                hintText: 'e.g. Jaswa',
                                prefixIcon:
                                    Icon(Icons.badge_outlined, size: 20),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          TextField(
                            controller: _email,
                            enabled: !_busy,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.mail_outline, size: 20),
                            ),
                            onSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _password,
                            enabled: !_busy,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              prefixIcon: Icon(Icons.lock_outline, size: 20),
                            ),
                            onSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _registering
                                          ? 'Create account'
                                          : 'Log in',
                                    ),
                            ),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _registering = !_registering;
                                      _error = null;
                                    }),
                            child: Text(_registering
                                ? 'Have an account? Log in'
                                : 'New here? Create an account'),
                          ),
                          if (_error != null) _ErrorBanner(message: _error!),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.registering});

  final bool registering;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppPalette.forest, AppPalette.forestDeep],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x331B4332),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPLIT CHAT',
            style: GoogleFonts.manrope(
              fontSize: 11,
              letterSpacing: 3.4,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFE4C776),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Settle up, ${registering ? 'together.' : 'simply.'}',
            style: GoogleFonts.fraunces(
              fontSize: 30,
              height: 1.08,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            registering
                ? 'Create an account with your email. Groups and expenses are '
                    'stored in the cloud, safe and shared.'
                : 'Log in to see your expense groups. Everything you track is '
                    'stored securely in the cloud.',
            style: GoogleFonts.manrope(
              fontSize: 13.5,
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppPalette.bad.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline,
              size: 18, color: AppPalette.bad),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.4,
                color: AppPalette.bad,
              ),
            ),
          ),
        ],
      ),
    );
  }
}