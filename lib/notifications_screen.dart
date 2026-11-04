import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  CollectionReference<Map<String, dynamic>> _col(String myUid) =>
      FirebaseFirestore.instance.collection('users').doc(myUid).collection('notifications');

  /// Deletes every notification of the current user (in chunks, Firestore batches max out at 500).
  Future<void> clearAll(BuildContext context, String myUid) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Clear all notifications?"),
        content: const Text("All your notifications will be permanently removed."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Clear all", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final db = FirebaseFirestore.instance;
      while (true) {
        final snap = await _col(myUid).limit(400).get();
        if (snap.docs.isEmpty) break;
        final batch = db.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Notifications cleared")));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't clear notifications: $e")));
      }
    }
  }

  /// Marks all unread notifications as read (removes the red badge on the bell).
  Future<void> markAllRead(BuildContext context, String myUid) async {
    try {
      final snap = await _col(myUid).where('read', isEqualTo: false).get();
      if (snap.docs.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        batch.update(d.reference, {'read': true});
      }
      await batch.commit();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't update notifications: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
        actions: [
          IconButton(
            tooltip: "Mark all as read",
            icon: const Icon(Icons.done_all),
            onPressed: () => markAllRead(context, myUid),
          ),
          IconButton(
            tooltip: "Clear all",
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => clearAll(context, myUid),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users').doc(myUid).collection('notifications')
            .orderBy('timestamp', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text("Couldn't load notifications: ${snapshot.error}", textAlign: TextAlign.center),
            ));
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text("No notifications yet"));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              // swipe left or right to delete a single notification
              return Dismissible(
                key: ValueKey(docs[i].id),
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                secondaryBackground: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) {
                  docs[i].reference.delete();
                },
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.red[50],
                    child: Icon(
                      data['type'] == 'like' ? Icons.favorite : Icons.notifications,
                      color: Colors.red,
                    ),
                  ),
                  title: Text(data['text'] ?? ''),
                  subtitle: data['timestamp'] != null
                      ? Text(_formatTime((data['timestamp'] as Timestamp).toDate()))
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (data['read'] == false)
                        Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                      IconButton(
                        tooltip: "Remove",
                        icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                        onPressed: () => docs[i].reference.delete(),
                      ),
                    ],
                  ),
                  onTap: () {
                    docs[i].reference.update({'read': true});
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "${diff.inHours}h ago";
    return "${diff.inDays}d ago";
  }
}
