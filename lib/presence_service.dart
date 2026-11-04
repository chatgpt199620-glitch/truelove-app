import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Writes my online/offline state to users/{uid}:
///   isOnline (bool) + lastSeen (server timestamp)
class PresenceService {
  /// set to true while an account is being deleted, so a late "online" write
  /// cannot re-create the profile document.
  static bool disabled = false;

  static Future<void> _write(bool online) async {
    if (disabled) return;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(u.uid).set({
        'isOnline': online,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // presence is best-effort, never crash the app because of it
    }
  }

  static Future<void> goOnline() => _write(true);
  static Future<void> goOffline() => _write(false);

  /// Compatibility: your settings_screen.dart calls PresenceService().setOnline(false)
  /// (e.g. before logout / delete account). Keep this so that code still compiles.
  Future<void> setOnline(bool online) => _write(online);
}

/// A user counts as online only if isOnline == true AND their heartbeat is
/// recent. This protects against crashes / dead batteries where the app never
/// got the chance to write "offline".
bool isOnlineNow(Map<String, dynamic>? user) {
  if (user == null || user['isOnline'] != true) return false;
  final ts = user['lastSeen'];
  if (ts is! Timestamp) return true; // just-written, server time not resolved yet
  return DateTime.now().difference(ts.toDate()).inMinutes < 8;
}

String _clock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

/// "Online", "Last seen just now", "Last seen today at 5:30 PM", ...
/// Returns '' when the user never had presence data (old accounts).
String presenceText(Map<String, dynamic>? user) {
  if (user == null) return '';
  if (isOnlineNow(user)) return 'Online';
  final ts = user['lastSeen'];
  if (ts is! Timestamp) return '';
  final d = ts.toDate();
  final now = DateTime.now();
  final diff = now.difference(d);
  if (diff.inMinutes < 1) return 'Last seen just now';
  if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes} min ago';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'Last seen today at ${_clock(d)}';
  if (days == 1) return 'Last seen yesterday at ${_clock(d)}';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return 'Last seen ${d.day} ${m[d.month - 1]}';
}

/// Small green (online) / grey (offline) dot.
class PresenceDot extends StatelessWidget {
  final bool online;
  final double size;
  const PresenceDot({super.key, required this.online, this.size = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: online ? Colors.green : Colors.grey,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }
}
