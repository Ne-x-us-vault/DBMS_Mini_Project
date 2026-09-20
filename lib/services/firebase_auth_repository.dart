import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;

import 'auth_repository.dart';

/// Firebase-backed [AuthRepository] using Email/Password authentication.
///
/// Account profiles live in Firestore:
/// - `users/{uid}` → `{displayName, email, createdAt}`
/// - `usernames/{name}` → `{uid}` — the global unique-username index.
///   Document IDs are [normalizeUsername] keys. Uniqueness is enforced by the
///   security rules (CREATE-only writes), so a second account can never claim
///   an already-used name, even under a race.
///
/// The `authState()` stream resolves each signed-in Firebase user against
/// that document, so the UI always has the account's *display name* — not
/// just the uid — and reacts to profile edits too.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final fa.FirebaseAuth _auth = fa.FirebaseAuth.instance;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  DocumentReference<Map<String, dynamic>> _usernameDoc(String name) =>
      _db.collection('usernames').doc(normalizeUsername(name));

  AuthUser _fromFirebase(fa.User u, Map<String, dynamic>? data) => AuthUser(
        uid: u.uid,
        email: u.email,
        displayName: (data?['displayName'] as String?) ?? '',
        createdAt:
            data?['createdAt'] is Timestamp ? (data!['createdAt'] as Timestamp).toDate() : null,
      );

  @override
  Stream<AuthUser?> authState() {
    final ctrl = StreamController<AuthUser?>();
    StreamSubscription<AuthUser?>? profileSub;

    void resolve(fa.User? u) {
      profileSub?.cancel();
      if (u == null) {
        ctrl.add(null);
        return;
      }
      profileSub = _userDoc(u.uid).snapshots().map((s) {
        return _fromFirebase(u, s.exists ? s.data() : null);
      }).listen(
        ctrl.add,
        onError: ctrl.addError,
      );
    }

    _auth.authStateChanges().listen(resolve,
        onError: ctrl.addError, onDone: () {
      profileSub?.cancel();
      ctrl.close();
    });
    return ctrl.stream;
  }

  @override
  Future<AuthUser> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    final name = displayName.trim();
    final key = normalizeUsername(name);
    if (key.isEmpty) {
      throw fa.FirebaseAuthException(
        code: 'invalid-display-name',
        message: 'A display name is required.',
      );
    }

    // Fast, friendly pre-check. The rules are still the source of truth:
    // if the name is taken after this read, the index write below is an
    // UPDATE and gets denied by the server.
    final taken = await _usernameDoc(key).get().then((s) => s.exists);
    if (taken) throw UsernameTakenException(name: name);

    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = cred.user!.uid;
    try {
      // create-if-absent: a granted CREATE reserves the name, a second writer
      // hits the denied UPDATE branch → UsernameTakenException.
      await _db.collection('usernames').doc(key).set({'uid': uid});
      await _userDoc(uid).set({
        'displayName': name,
        'email': email.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'already-exists') {
        // Release the half-created account so the email stays usable.
        await cred.user?.delete();
        throw UsernameTakenException(name: name);
      }
      rethrow;
    }
    return AuthUser(
      uid: uid,
      email: email.trim(),
      displayName: name,
    );
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final u = cred.user!;
    final snap = await _userDoc(u.uid).get();
    if (snap.exists) {
      final user = _fromFirebase(u, snap.data());
      // Self-heal: accounts created before the usernames index existed get
      // their name reserved on first sign-in (idempotent, best-effort).
      await _ensureUsernameIndex(u.uid, user.displayName);
      return user;
    }
    // Repair path: an account whose profile write failed (or was created
    // out-of-band). Recreate the profile under a unique username.
    final fallback = await _uniqueFallbackName(u.email?.split('@').first ?? 'Me');
    final batch = _db.batch();
    batch.set(_db.collection('usernames').doc(normalizeUsername(fallback)),
        {'uid': u.uid});
    batch.set(_userDoc(u.uid), {
      'displayName': fallback,
      'email': u.email,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return AuthUser(uid: u.uid, email: u.email, displayName: fallback);
  }

  Future<String> _uniqueFallbackName(String base) async {
    var candidate = base;
    var i = 2;
    while (await _db
        .collection('usernames')
        .doc(normalizeUsername(candidate))
        .get()
        .then((s) => s.exists)) {
      candidate = '$base$i';
      i++;
    }
    return candidate;
  }

  /// Reserves `usernames/{key}` → `{uid}` if it isn't reserved yet. Used to
  /// backfill accounts that predate the index; failures are ignored because
  /// the row may already exist (or belong to a different account, in which
  /// case the genuinely unique constraint correctly stands).
  Future<void> _ensureUsernameIndex(String uid, String displayName) async {
    final name = displayName.trim();
    if (name.isEmpty) return;
    try {
      await _db
          .collection('usernames')
          .doc(normalizeUsername(name))
          .set({'uid': uid});
    } catch (_) {
      // create-if-absent: an already-exists row (ours or a collision) is OK.
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> updateProfile({required String displayName}) async {
    final u = _auth.currentUser;
    if (u == null) return;
    final name = displayName.trim();
    final oldSnap = await _userDoc(u.uid).get();
    final oldName = oldSnap.exists
        ? ((oldSnap.data()?['displayName'] as String?) ?? '')
        : '';
    final oldKey = normalizeUsername(oldName);
    final newKey = normalizeUsername(name);
    if (newKey.isEmpty) return;
    if (oldKey == newKey) {
      await _userDoc(u.uid).set(
        {'displayName': name},
        SetOptions(merge: true),
      );
      return;
    }
    final newTaken = await _usernameDoc(newKey).get().then((s) => s.exists);
    if (newTaken) throw UsernameTakenException(name: name);
    // Renaming is one atomic batch: release the old key, claim the new one,
    // update the profile.
    final batch = _db.batch();
    batch.delete(_usernameDoc(oldKey));
    batch.set(_db.collection('usernames').doc(newKey), {'uid': u.uid});
    batch.set(
      _userDoc(u.uid),
      {'displayName': name},
      SetOptions(merge: true),
    );
    await batch.commit();
  }
}