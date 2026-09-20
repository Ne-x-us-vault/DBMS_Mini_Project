import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  /// Creates the Firebase Auth user plus a `users/{uid}` profile doc.
  ///
  /// Role assignment: the very first user in the project becomes `admin`;
  /// everyone else becomes `member` (an admin can promote later).
  static Future<String> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final auth = FirebaseAuth.instance;
    final cred = await auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final uid = cred.user!.uid;
    await cred.user!.updateDisplayName(name.trim());

    final db = FirebaseFirestore.instance;
    final existing = await db.collection('users').limit(1).get();
    final role = existing.docs.isEmpty ? 'admin' : 'member';
    await db.collection('users').doc(uid).set({
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'role': role,
    });
    return role;
  }
}