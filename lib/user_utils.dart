import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

const List<String> kGenders = ['Male', 'Female', 'Non-binary', 'Other'];

// ---------------------------------------------------------------------------
// Username helpers
// ---------------------------------------------------------------------------
String normalizeUsername(String raw) => raw.trim().toLowerCase().replaceAll('@', '');

String? validateUsername(String raw) {
  final u = normalizeUsername(raw);
  if (u.isEmpty) return 'Please choose a username.';
  if (u.length < 3 || u.length > 20) return 'Username must be 3-20 characters.';
  if (!RegExp(r'^[a-z0-9._]+$').hasMatch(u)) {
    return 'Use only letters, numbers, dot (.) and underscore (_).';
  }
  return null;
}

/// Reserves [newUsername] for [uid] (unique across all users) and saves it on
/// the user's document. Returns null on success, or an error message.
Future<String?> claimUsername({
  required String uid,
  required String newUsername,
  String? oldUsername,
}) async {
  final err = validateUsername(newUsername);
  if (err != null) return err;

  final fresh = normalizeUsername(newUsername);
  final old = (oldUsername ?? '').trim().toLowerCase();
  final db = FirebaseFirestore.instance;
  final newRef = db.collection('usernames').doc(fresh);
  final userRef = db.collection('users').doc(uid);

  try {
    await db.runTransaction((tx) async {
      final snap = await tx.get(newRef);
      if (snap.exists && snap.data()?['uid'] != uid) {
        throw Exception('USERNAME_TAKEN');
      }
      tx.set(newRef, {'uid': uid});
      if (old.isNotEmpty && old != fresh) {
        tx.delete(db.collection('usernames').doc(old));
      }
      tx.set(userRef, {'username': fresh}, SetOptions(merge: true));
    });
    return null;
  } catch (e) {
    if (e.toString().contains('USERNAME_TAKEN')) return 'That username is already taken.';
    return 'Could not save username: $e';
  }
}

// ---------------------------------------------------------------------------
// Photo upload (Firebase Storage). Throws on failure so the real error shows.
// ---------------------------------------------------------------------------
// (old Firebase Storage version - kept, but no longer used because it needs a paid plan)
Future<String> uploadProfilePhotoFirebase(File file, String uid, String fileName) async {
  final ref = FirebaseStorage.instance.ref().child('profile_photos/$uid/$fileName');
  await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
  return await ref.getDownloadURL();
}

// ---------------------------------------------------------------------------
// Profile data helpers
// ---------------------------------------------------------------------------
int? ageFromDob(dynamic dob) {
  if (dob is! Timestamp) return null;
  final d = dob.toDate();
  final now = DateTime.now();
  int age = now.year - d.year;
  if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
  return age;
}

List<String> photosOf(Map<String, dynamic> user) {
  final list = (user['photos'] as List?)?.whereType<String>().toList();
  if (list != null && list.isNotEmpty) return list;
  final p = user['photoUrl'];
  return (p is String && p.isNotEmpty) ? [p] : [];
}

// ---------------------------------------------------------------------------
// Connection request actions (used by the profile-view, discover and requests screens)
// Request document id is always "<fromUid>_<toUid>".
// ---------------------------------------------------------------------------
class RequestService {
  static final _db = FirebaseFirestore.instance;
  static String get _me => FirebaseAuth.instance.currentUser!.uid;

  static Future<void> send(String otherUid) async {
    final myUid = _me;

    // If the other person has already sent ME a pending request, sending one
    // back should simply accept theirs (like Instagram / Facebook), instead of
    // creating a duplicate request in the opposite direction.
    final reverse = await _db.collection('requests').doc('${otherUid}_$myUid').get();
    if (reverse.exists && reverse.data()?['status'] == 'pending') {
      await accept(otherUid);
      return;
    }

    final myDoc = await _db.collection('users').doc(myUid).get();
    final myName = myDoc.data()?['name'] ?? 'Someone';

    await _db.collection('requests').doc('${myUid}_$otherUid').set({
      'from': myUid,
      'to': otherUid,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });

    await _db.collection('users').doc(otherUid).collection('notifications').add({
      'type': 'request',
      'text': '$myName sent you a connection request',
      'fromUid': myUid,
      'read': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> cancel(String otherUid) async {
    await _db.collection('requests').doc('${_me}_$otherUid').delete();
  }

  /// Accepts the pending request that [fromUid] sent to me.
  /// Uses ONE batch so the request status, the match and the notification are
  /// written together (all succeed or all fail). Errors are NOT swallowed:
  /// callers must catch and show them.
  static Future<void> accept(String fromUid) async {
    final myUid = _me;
    final myDoc = await _db.collection('users').doc(myUid).get();
    final myName = myDoc.data()?['name'] ?? 'Someone';
    final matchId = ([myUid, fromUid]..sort()).join('_');

    final batch = _db.batch();
    batch.update(_db.collection('requests').doc('${fromUid}_$myUid'), {'status': 'accepted'});
    batch.set(_db.collection('matches').doc(matchId), {
      'users': [myUid, fromUid],
      'timestamp': FieldValue.serverTimestamp(),
    });
    batch.set(_db.collection('users').doc(fromUid).collection('notifications').doc(), {
      'type': 'accepted',
      'text': '$myName accepted your request! 🎉',
      'fromUid': myUid,
      'read': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  static Future<void> decline(String fromUid) async {
    await _db.collection('requests').doc('${fromUid}_$_me').update({'status': 'declined'});
  }

  /// Ends the connection with [otherUid]:
  ///  - deletes the match (removes them from Messages / Friends list)
  ///  - deletes the request in BOTH directions (removes them from Accepted tab,
  ///    and lets either person send a fresh request later)
  ///  - deletes the chat messages (best effort)
  /// After this, the Firestore rules also block sending messages.
  static Future<void> unmatch(String otherUid) async {
    final myUid = _me;
    final matchId = ([myUid, otherUid]..sort()).join('_');
    final batch = _db.batch();

    // queries (not .get() on a single doc) so a missing document never throws
    final mine = await _db.collection('matches').where('users', arrayContains: myUid).get();
    for (final d in mine.docs) {
      if (d.id == matchId) batch.delete(d.reference);
    }
    final sent = await _db.collection('requests')
        .where('from', isEqualTo: myUid).where('to', isEqualTo: otherUid).get();
    final recv = await _db.collection('requests')
        .where('from', isEqualTo: otherUid).where('to', isEqualTo: myUid).get();
    for (final d in [...sent.docs, ...recv.docs]) {
      batch.delete(d.reference);
    }
    await batch.commit();

    // clean up the chat history (not critical, so errors are ignored)
    try {
      final msgs = _db.collection('chats').doc(matchId).collection('messages');
      while (true) {
        final snap = await msgs.limit(400).get();
        if (snap.docs.isEmpty) break;
        final b = _db.batch();
        for (final d in snap.docs) {
          b.delete(d.reference);
        }
        await b.commit();
      }
    } catch (_) {}
  }
}


// ---------------------------------------------------------------------------
// FREE photo upload using Cloudinary (unsigned preset, no server, no card)
// 1) cloudinary.com -> copy your "Cloud name"
// 2) Settings > Upload > Upload presets > Add > Signing mode: Unsigned > save
// 3) paste both values below
// ---------------------------------------------------------------------------
const String kCloudName = 'uc1d7sgs';
const String kUploadPreset = 'truelove';

/// Uploads [file] and returns the image URL. Throws with the real reason on failure.
/// The real reason is also printed in the terminal as "UPLOAD ERROR: ..." so you can
/// read it even when a screen only shows "photo failed".
/// Text of the most recent upload failure (empty when the last upload worked).
/// Useful for screens that only receive "null" when an upload fails.
String lastUploadError = '';

Future<String> uploadProfilePhoto(File file, String uid, String fileName) async {
  try {
    lastUploadError = '';
    return await _uploadToCloudinary(file, uid, fileName);
  } catch (e) {
    lastUploadError = e.toString();
    debugPrint('UPLOAD ERROR: $e');
    rethrow;
  }
}

Future<String> _uploadToCloudinary(File file, String uid, String fileName) async {
  if (kCloudName.startsWith('YOUR_') || kUploadPreset.startsWith('YOUR_')) {
    throw Exception('Cloudinary is not set up yet. Put your cloud name and preset in user_utils.dart');
  }
  final req = http.MultipartRequest(
    'POST',
    Uri.parse('https://api.cloudinary.com/v1_1/$kCloudName/image/upload'),
  )
    ..fields['upload_preset'] = kUploadPreset
    ..fields['folder'] = 'profile_photos/$uid'
    ..files.add(await http.MultipartFile.fromPath('file', file.path));

  final res = await http.Response.fromStream(await req.send());
  if (res.statusCode != 200) {
    throw Exception('Upload failed (${res.statusCode}): ${res.body}');
  }
  final url = jsonDecode(res.body)['secure_url'] as String;
  // auto format + quality, max width 800px => small & fast, saves free quota
  return url.replaceFirst('/upload/', '/upload/c_limit,w_800,f_auto,q_auto/');
}

/// OPTIONAL user cap (see earlier message). Not used unless you call it.
Future<String?> reserveUserSlot(String uid) async {
  final db = FirebaseFirestore.instance;
  final userRef = db.collection('users').doc(uid);
  final statsRef = db.collection('config').doc('stats');
  final limitsRef = db.collection('config').doc('limits');
  try {
    return await db.runTransaction<String?>((tx) async {
      final user = await tx.get(userRef);
      if (user.data()?['slotReserved'] == true) return null;
      final stats = await tx.get(statsRef);
      final limits = await tx.get(limitsRef);
      final count = (stats.data()?['userCount'] as int?) ?? 0;
      final max = (limits.data()?['maxUsers'] as int?) ?? 300;
      if (count >= max) {
        return "TrueLove is full right now. Please try again later.";
      }
      tx.set(statsRef, {'userCount': count + 1}, SetOptions(merge: true));
      tx.set(userRef, {'slotReserved': true}, SetOptions(merge: true));
      return null;
    });
  } catch (e) {
    return 'Could not check availability: $e';
  }
}
