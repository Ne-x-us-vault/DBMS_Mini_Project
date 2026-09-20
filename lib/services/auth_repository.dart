/// The signed-in account: who the user is (from the `users/{uid}` document).
class AuthUser {
  const AuthUser({
    required this.uid,
    this.email,
    required this.displayName,
    this.createdAt,
  });

  final String uid;
  final String? email;
  final String displayName;
  final DateTime? createdAt;
}

/// Abstraction over authentication and the account document.
///
/// The production implementation uses Firebase Email/Password auth and keeps
/// the profile in `users/{uid}` (Firestore); a test double is not required
/// because the UI drives this only through [authState].
abstract class AuthRepository {
  /// Emits the signed-in account, or `null` while signed out. Emits again
  /// whenever the account's profile (`users/{uid}`) changes.
  Stream<AuthUser?> authState();

  /// Creates a new account with [email]/[password] and writes the account's
  /// profile document (`users/{uid}`: `displayName`, `email`, `createdAt`).
  /// Throws a [FirebaseAuthException] (codes like `email-already-in-use`,
  /// `weak-password`, `invalid-email`) on failure.
  Future<AuthUser> register({
    required String displayName,
    required String email,
    required String password,
  });

  /// Signs an existing account in. Throws a [FirebaseAuthException]
  /// (`user-not-found`, `wrong-password`, `invalid-email`, …) on failure.
  Future<AuthUser> signIn({required String email, required String password});

  /// Signs the account out. The `authState()` stream emits `null`.
  Future<void> signOut();

  /// Updates the account's display name in `users/{uid}`.
  Future<void> updateProfile({required String displayName});
}