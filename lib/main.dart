import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'screens/home_page.dart';
import 'screens/login_screen.dart';
import 'services/auth_repository.dart';
import 'services/firebase_auth_repository.dart';
import 'services/firestore_repository.dart';
import 'services/group_repository.dart';
import 'services/local_session.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SplitChatApp());
}

class SplitChatApp extends StatelessWidget {
  const SplitChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Split Chat',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const FirebaseBootstrap(),
    );
  }
}

/// Initializes Firebase *inside* the widget tree so the app always renders
/// something (a "Connecting…" screen, then the real error with a Retry button
/// if the cloud is unreachable) instead of a white screen.
class FirebaseBootstrap extends StatefulWidget {
  const FirebaseBootstrap({super.key});

  @override
  State<FirebaseBootstrap> createState() => _FirebaseBootstrapState();
}

class _FirebaseBootstrapState extends State<FirebaseBootstrap> {
  Future<void>? _init;

  @override
  void initState() {
    super.initState();
    _init = _initialize();
  }

  Future<void> _initialize() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  void _retry() {
    setState(() => _init = _initialize());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _ConnectingScreen();
        }
        if (snap.hasError) {
          debugPrint('Firebase bootstrap failed: ${snap.error}');
          return _FirebaseErrorScreen(error: snap.error!, onRetry: _retry);
        }
        return AppBootstrap(
          auth: FirebaseAuthRepository(),
          repository: FirestoreGroupRepository(),
          local: LocalSession(),
        );
      },
    );
  }
}

class _ConnectingScreen extends StatelessWidget {
  const _ConnectingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Connecting…'),
          ],
        ),
      ),
    );
  }
}

/// Shows the real exception (type, error code, message) with a plain-English
/// hint for common cases and a Retry button.
class _FirebaseErrorScreen extends StatelessWidget {
  const _FirebaseErrorScreen({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  String _errorCode(Object e) {
    if (e is FirebaseException) return e.code;
    if (e is PlatformException) return e.code;
    return '';
  }

  String _errorMessage(Object e) {
    if (e is FirebaseException) return e.message ?? e.toString();
    if (e is PlatformException) return e.message ?? e.toString();
    return e.toString();
  }

  String get _hint {
    final code = _errorCode(error);
    final msg = _errorMessage(error);
    if (code == 'operation-not-allowed' || code == 'admin-restricted-operation') {
      return 'Email/Password sign-in is not enabled. Enable it in the Firebase '
          'console: Authentication → Sign-in method → Email/Password.';
    }
    if (code == 'permission-denied') {
      return 'Security rules are blocking access. Deploy the Firestore rules '
          '(firebase deploy --only firestore:rules).';
    }
    if (code == 'not-found' ||
        msg.contains('database does not exist') ||
        msg.contains('The Cloud Firestore database is not available')) {
      return 'The Firestore database does not exist. Create it in the Firebase '
          'console: Firestore Database → Create database.';
    }
    if (code == 'unavailable' || code == 'network-request-failed') {
      return 'No internet connection on this device. Check Wi-Fi/data and try again.';
    }
    if (msg.contains('invalid api key') || msg.contains('app not found')) {
      return 'The Firebase config does not match this app. Rerun '
          'flutterfire configure --project=<your project id>.';
    }
    return 'See the error details below. Try again once you are online.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.cloud_off_outlined,
                    size: 56, color: theme.colorScheme.error),
                const SizedBox(height: 12),
                Text(
                  'Could not connect to Firebase',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      'Type:      ${error.runtimeType}\n'
                      'Code:      ${_errorCode(error)}\n'
                      'Message:   ${_errorMessage(error)}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Decides between the login screen and the home group list, based on the
/// signed-in account. Sign-up/log-in/sign-out all flow through
/// [AuthRepository.authState] so the UI follows the auth session automatically.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({
    super.key,
    required this.auth,
    required this.repository,
    required this.local,
  });

  final AuthRepository auth;
  final GroupRepository repository;
  final LocalSession local;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  AuthUser? _user;
  bool _localReady = false;

  @override
  void initState() {
    super.initState();
    widget.local.load().then((_) {
      if (!mounted) return;
      setState(() => _localReady = true);
    });
    widget.auth.authState().listen((user) {
      if (!mounted) return;
      if (user == null) {
        // Signed out: forget on-device identity + the open group.
        widget.local.setDisplayName(null);
        widget.local.setGroupId(null);
      } else {
        // Signed in: mirror the cloud profile name for group creation.
        widget.local.setDisplayName(user.displayName);
      }
      setState(() => _user = user);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_localReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_user == null) {
      return LoginScreen(auth: widget.auth);
    }
    return HomePage(
      auth: widget.auth,
      user: _user!,
      repository: widget.repository,
      local: widget.local,
    );
  }
}