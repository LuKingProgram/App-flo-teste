import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Initializes Firebase when the Android app has a Firebase config installed.
/// The local cycle tracker remains usable while the project is being configured.
class FirebaseService {
  FirebaseService._();

  static bool get isReady => Firebase.apps.isNotEmpty;

  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
    } on FirebaseException {
      // Firebase Console configuration has not been added to this checkout yet.
    }
  }

  static FirebaseAuth get auth {
    _requireReady();
    return FirebaseAuth.instance;
  }

  static FirebaseFirestore get firestore {
    _requireReady();
    return FirebaseFirestore.instance;
  }

  static void _requireReady() {
    if (!isReady) {
      throw StateError(
        'Firebase ainda não está configurado. Adicione a configuração do projeto Firebase Android.',
      );
    }
  }
}

class AccountService {
  Stream<User?> get authStateChanges => FirebaseService.auth.authStateChanges();

  User? get currentUser => FirebaseService.auth.currentUser;

  Future<UserCredential> createAccount({
    required String email,
    required String password,
  }) => FirebaseService.auth.createUserWithEmailAndPassword(
    email: email.trim(),
    password: password,
  );

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) => FirebaseService.auth.signInWithEmailAndPassword(
    email: email.trim(),
    password: password,
  );

  Future<void> signOut() => FirebaseService.auth.signOut();
}

/// Stores a user's private cycle data under their Firebase Authentication UID.
/// Pairing data is deliberately kept out of this document and can be added with
/// restrictive Firestore rules when the sharing flow is implemented.
class CycleCloudStore {
  CollectionReference<Map<String, dynamic>> _collection(String uid) =>
      FirebaseService.firestore
          .collection('users')
          .doc(uid)
          .collection('cycle');

  Future<void> save({
    required String uid,
    required Map<String, dynamic> data,
  }) => _collection(uid).doc('private').set({
    ...data,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  Future<Map<String, dynamic>?> load(String uid) async {
    final snapshot = await _collection(uid).doc('private').get();
    return snapshot.data();
  }
}

class PairConnection {
  const PairConnection({
    required this.code,
    required this.ownerUid,
    required this.guestUid,
    required this.status,
    required this.expiresAt,
  });

  final String code;
  final String ownerUid;
  final String? guestUid;
  final String status;
  final DateTime? expiresAt;

  bool get isOwner => FirebaseService.auth.currentUser?.uid == ownerUid;
  bool get isActive => status == 'active' && guestUid != null;
  bool get isPending => status == 'pending';

  factory PairConnection.fromMap(String code, Map<String, dynamic> data) =>
      PairConnection(
        code: code,
        ownerUid: data['ownerUid'] as String? ?? '',
        guestUid: data['guestUid'] as String?,
        status: data['status'] as String? ?? 'closed',
        expiresAt: (data['expiresAt'] as Timestamp?)?.toDate(),
      );
}

/// One-way cycle sharing: the person who creates the invitation owns and
/// edits the source cycle; the invited account receives live, read-only data.
class CyclePairService {
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const invitationLifetime = Duration(minutes: 30);

  DocumentReference<Map<String, dynamic>> _pair(String code) =>
      FirebaseService.firestore.collection('pairs').doc(code);

  DocumentReference<Map<String, dynamic>> _membership(String uid) =>
      FirebaseService.firestore
          .collection('users')
          .doc(uid)
          .collection('pair')
          .doc('current');

  DocumentReference<Map<String, dynamic>> _cycle(String code) =>
      _pair(code).collection('cycle').doc('current');

  String _newCode() {
    final random = Random.secure();
    return List.generate(
      10,
      (_) => _alphabet[random.nextInt(_alphabet.length)],
    ).join();
  }

  Future<String> createInvite({
    required String uid,
    required Map<String, dynamic> cycleData,
  }) async {
    final code = _newCode();
    final pairRef = _pair(code);
    final membershipRef = _membership(uid);
    final now = DateTime.now().toUtc();

    await FirebaseService.firestore.runTransaction((transaction) async {
      final membership = await transaction.get(membershipRef);
      DocumentSnapshot<Map<String, dynamic>>? oldPair;
      DocumentReference<Map<String, dynamic>>? oldPairRef;
      if (membership.exists) {
        final oldCode = membership.data()?['pairId'] as String?;
        if (oldCode != null) {
          oldPairRef = _pair(oldCode);
          oldPair = await transaction.get(oldPairRef);
        }
      }

      if (oldPair?.exists == true) {
        final oldData = oldPair!.data()!;
        final expiry = (oldData['expiresAt'] as Timestamp?)?.toDate();
        final stalePending =
            oldData['status'] == 'pending' &&
            expiry != null &&
            !expiry.isAfter(now);
        if (oldData['status'] != 'closed' && !stalePending) {
          throw StateError(
            'Este perfil já está conectado ou tem um convite ativo.',
          );
        }
        if (oldData['ownerUid'] == uid) {
          transaction.delete(_cycle(oldPairRef!.id));
          transaction.delete(oldPairRef);
        }
      }

      transaction.set(pairRef, {
        'ownerUid': uid,
        'guestUid': null,
        'status': 'pending',
        'createdAt': Timestamp.fromDate(now),
        'expiresAt': Timestamp.fromDate(now.add(invitationLifetime)),
      });
      transaction.set(membershipRef, {'pairId': code, 'role': 'owner'});
    });

    await saveCycle(code: code, uid: uid, data: cycleData);
    return code;
  }

  Future<String> joinInvite({required String uid, required String code}) async {
    final normalizedCode = code.trim().toUpperCase();
    final pairRef = _pair(normalizedCode);
    final membershipRef = _membership(uid);
    final now = DateTime.now().toUtc();

    await FirebaseService.firestore.runTransaction((transaction) async {
      final invitation = await transaction.get(pairRef);
      final currentMembership = await transaction.get(membershipRef);
      DocumentSnapshot<Map<String, dynamic>>? oldPair;
      DocumentReference<Map<String, dynamic>>? oldPairRef;
      if (currentMembership.exists) {
        final oldCode = currentMembership.data()?['pairId'] as String?;
        if (oldCode != null && oldCode != normalizedCode) {
          oldPairRef = _pair(oldCode);
          oldPair = await transaction.get(oldPairRef);
        }
      }

      if (oldPair?.exists == true && oldPair!.data()?['status'] != 'closed') {
        throw StateError('Esta conta já está conectada a outro ciclo.');
      }
      final data = invitation.data();
      if (data == null ||
          data['status'] != 'pending' ||
          data['guestUid'] != null ||
          data['ownerUid'] == uid) {
        throw StateError('Código inválido, expirado ou já utilizado.');
      }
      final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
      if (expiresAt == null || !expiresAt.isAfter(now)) {
        throw StateError('Este código expirou. Peça um novo convite.');
      }

      if (oldPair?.exists == true && oldPair!.data()?['ownerUid'] == uid) {
        transaction.delete(oldPairRef!);
      }
      transaction.update(pairRef, {
        'guestUid': uid,
        'status': 'active',
        'joinedAt': Timestamp.fromDate(now),
      });
      transaction.set(membershipRef, {
        'pairId': normalizedCode,
        'role': 'guest',
      });
    });
    return normalizedCode;
  }

  Future<PairConnection?> current(String uid) async {
    final membershipRef = _membership(uid);
    final membership = await membershipRef.get();
    final code = membership.data()?['pairId'] as String?;
    if (code == null) return null;
    final pairRef = _pair(code);
    final pairSnapshot = await pairRef.get();
    final data = pairSnapshot.data();
    if (data == null) {
      await membershipRef.delete();
      return null;
    }
    final connection = PairConnection.fromMap(code, data);
    if (connection.status == 'closed') {
      if (connection.ownerUid == uid) {
        await closePair(code: code, uid: uid, isOwner: true);
      } else {
        await membershipRef.delete();
      }
      return null;
    }
    return connection;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchPair(String code) =>
      _pair(code).snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchCycle(String code) =>
      _cycle(code).snapshots();

  Future<void> saveCycle({
    required String code,
    required String uid,
    required Map<String, dynamic> data,
  }) => _cycle(code).set({
    ...data,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  Future<void> closePair({
    required String code,
    required String uid,
    required bool isOwner,
  }) async {
    final batch = FirebaseService.firestore.batch();
    final pairRef = _pair(code);
    batch.delete(_membership(uid));
    if (isOwner) {
      batch.delete(_cycle(code));
      batch.delete(pairRef);
    } else {
      batch.update(pairRef, {
        'status': 'closed',
        'closedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> clearMembership(String uid) => _membership(uid).delete();
}
