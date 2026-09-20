import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;

import 'auth_repository.dart';

/// Firebase-backed [AuthRepository] using Email/Password authentication.
///
/// Account profiles live in Firestore:
/// - `users/{uid}` → `{displayName, email, createdAt}`
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
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = cred.user!.uid;
    await _userDoc(uid).set({
      'displayName': displayName.trim(),
      'email': email.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return AuthUser(
      uid: uid,
      email: email.trim(),
      displayName: displayName.trim(),
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
      return _fromFirebase(u, snap.data());
    }
    final fallback = u.email?.split('@').first ?? 'Me';
    await _userDoc(u.uid).set({
      'displayName': fallback,
      'email': u.email,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return AuthUser(uid: u.uid, email: u.email, displayName: fallback);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> updateProfile({required String displayName}) async {
    final u = _auth.currentUser;
    if (u == null) return;
    await _userDoc(u.uid).set(
      {'displayName': displayName.trim()},
      SetOptions(merge: true),
    );
  }
}