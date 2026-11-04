import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart'; // StartupGate
import 'presence_service.dart';

/// Complete "Delete account" flow. Call it from Settings:
///     onTap: () => deleteAccountFlow(context),
///
/// Order (important, so nothing is left half-deleted):
///  1. confirm
///  2. re-login check (Firebase requires a recent login to delete an account)
///  3. delete requests, matches, chats, notifications, blocked list, username
///  4. delete the profile document
///  5. delete the login (Firebase Auth user)
Future<void> deleteAccountFlow(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  // ---- 1) confirm -------------------------------------------------------
  final confirm = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text("Delete account?"),
      content: const Text(
        "This permanently deletes your profile, matches, chats and requests. "
        "This cannot be undone.",
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text("Delete", style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;

  // ---- 2) re-authenticate FIRST (before anything is deleted) --------------
  final ok = await _reauthenticate(context, user);
  if (!ok || !context.mounted) return;

  // ---- progress dialog -----------------------------------------------------
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );

  PresenceService.disabled = true; // stop "online" writes from re-creating the profile
  try {
    await _deleteAllMyData(user.uid);
    await user.delete(); // 5) delete the login itself

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close progress dialog
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const StartupGate()),
      (route) => false,
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // close progress dialog
      _snack(context, "Couldn't fully delete account: $e");
    }
  } finally {
    PresenceService.disabled = false;
  }
}

// ---------------------------------------------------------------------------
// Data deletion
// ---------------------------------------------------------------------------
Future<void> _deleteDocs(List<DocumentReference> refs) async {
  final db = FirebaseFirestore.instance;
  for (var i = 0; i < refs.length; i += 400) {
    final batch = db.batch();
    for (final r in refs.skip(i).take(400)) {
      batch.delete(r);
    }
    await batch.commit();
  }
}

Future<void> _deleteCollection(CollectionReference col) async {
  while (true) {
    final snap = await col.limit(400).get();
    if (snap.docs.isEmpty) break;
    await _deleteDocs(snap.docs.map((d) => d.reference).toList());
  }
}

Future<void> _deleteAllMyData(String uid) async {
  final db = FirebaseFirestore.instance;
  final userRef = db.collection('users').doc(uid);

  // remember the username so we can release it
  final me = await userRef.get();
  final username = ((me.data()?['username'] as String?) ?? '').trim().toLowerCase();

  // connection requests (sent AND received)
  final sent = await db.collection('requests').where('from', isEqualTo: uid).get();
  final recv = await db.collection('requests').where('to', isEqualTo: uid).get();
  await _deleteDocs([...sent.docs, ...recv.docs].map((d) => d.reference).toList());

  // matches + their chat messages
  final matches = await db.collection('matches').where('users', arrayContains: uid).get();
  for (final m in matches.docs) {
    await _deleteCollection(db.collection('chats').doc(m.id).collection('messages'));
  }
  await _deleteDocs(matches.docs.map((d) => d.reference).toList());

  // my own sub-collections
  await _deleteCollection(userRef.collection('notifications'));
  await _deleteCollection(userRef.collection('blocked'));

  // release the username so someone else can use it
  if (username.isNotEmpty) {
    final uref = db.collection('usernames').doc(username);
    final us = await uref.get();
    if (us.exists && us.data()?['uid'] == uid) await uref.delete();
  }

  // finally the profile document
  await userRef.delete();
}

// ---------------------------------------------------------------------------
// Re-authentication (email+password OR phone OTP)
// ---------------------------------------------------------------------------
Future<bool> _reauthenticate(BuildContext context, User user) async {
  final providers = user.providerData.map((p) => p.providerId).toList();

  try {
    if (providers.contains('password') && user.email != null) {
      final pwd = await _askText(
        context,
        title: "Confirm it's you",
        hint: "Enter your password",
        obscure: true,
      );
      if (pwd == null || pwd.isEmpty) return false;
      final cred = EmailAuthProvider.credential(email: user.email!, password: pwd);
      await user.reauthenticateWithCredential(cred);
      return true;
    }

    if (providers.contains('phone') && user.phoneNumber != null) {
      return await _reauthPhone(context, user);
    }
    return true; // unknown provider: just try
  } on FirebaseAuthException catch (e) {
    if (context.mounted) {
      final wrong = e.code == 'wrong-password' || e.code == 'invalid-credential';
      _snack(context, wrong ? "Wrong password. Account not deleted." : "Couldn't verify you: ${e.message}");
    }
    return false;
  } catch (e) {
    if (context.mounted) _snack(context, "Couldn't verify you: $e");
    return false;
  }
}

Future<bool> _reauthPhone(BuildContext context, User user) async {
  final phone = user.phoneNumber!;
  final done = Completer<bool>();

  void finish(bool v) {
    if (!done.isCompleted) done.complete(v);
  }

  await FirebaseAuth.instance.verifyPhoneNumber(
    phoneNumber: phone,
    verificationCompleted: (cred) async {
      try {
        await user.reauthenticateWithCredential(cred);
        finish(true);
      } catch (_) {
        finish(false);
      }
    },
    verificationFailed: (e) {
      if (context.mounted) _snack(context, "Couldn't send OTP: ${e.message}");
      finish(false);
    },
    codeSent: (verificationId, _) async {
      if (!context.mounted) return finish(false);
      final code = await _askText(
        context,
        title: "Confirm it's you",
        hint: "Enter the OTP sent to $phone",
        obscure: false,
      );
      if (done.isCompleted) return;
      if (code == null || code.trim().isEmpty) return finish(false);
      try {
        final cred = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code.trim());
        await user.reauthenticateWithCredential(cred);
        finish(true);
      } catch (e) {
        if (context.mounted) _snack(context, "Wrong or expired OTP. Account not deleted.");
        finish(false);
      }
    },
    codeAutoRetrievalTimeout: (_) {},
  );
  return done.future;
}

// ---------------------------------------------------------------------------
// small helpers
// ---------------------------------------------------------------------------
Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String hint,
  required bool obscure,
}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        obscureText: obscure,
        autofocus: true,
        keyboardType: obscure ? TextInputType.visiblePassword : TextInputType.number,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text("Confirm")),
      ],
    ),
  );
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
