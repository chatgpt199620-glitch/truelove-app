import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
import 'user_profile_screen.dart';
import 'presence_service.dart';
import 'unmatch_helper.dart';
import 'whatsapp_theme.dart';

/// "Messages" tab: list of connected people with last message preview.
class MatchesScreen extends StatelessWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: kWaHeaderColor,
        foregroundColor: Colors.white,
        title: const Text("Messages"),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('matches')
              .where('users', arrayContains: myUid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text("Couldn't load matches: ${snapshot.error}", textAlign: TextAlign.center),
                ),
              );
            }
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final docs = [...snapshot.data!.docs]..sort((a, b) {
                final ta = (a.data() as Map<String, dynamic>)['timestamp'];
                final tb = (b.data() as Map<String, dynamic>)['timestamp'];
                final ma = ta is Timestamp ? ta.millisecondsSinceEpoch : DateTime.now().millisecondsSinceEpoch;
                final mb = tb is Timestamp ? tb.millisecondsSinceEpoch : DateTime.now().millisecondsSinceEpoch;
                return mb.compareTo(ma);
              });

            if (docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    const Text("No connections yet", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text("Accepted requests appear here so you can chat.", style: TextStyle(color: Colors.grey[600])),
                  ],
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
              itemBuilder: (context, i) {
                final data = docs[i].data() as Map<String, dynamic>;
                final users = List<String>.from(data['users']);
                final otherUid = users.firstWhere((u) => u != myUid);
                return _ChatTile(key: ValueKey(docs[i].id), myUid: myUid, otherUid: otherUid);
              },
            );
          },
        ),
      ),
    );
  }
}

class _ChatTile extends StatefulWidget {
  final String myUid;
  final String otherUid;
  const _ChatTile({super.key, required this.myUid, required this.otherUid});

  @override
  State<_ChatTile> createState() => _ChatTileState();
}

class _ChatTileState extends State<_ChatTile> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> userStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> lastMsgStream;

  @override
  void initState() {
    super.initState();
    final db = FirebaseFirestore.instance;
    userStream = db.collection('users').doc(widget.otherUid).snapshots();
    final chatId = ([widget.myUid, widget.otherUid]..sort()).join('_');
    lastMsgStream = db
        .collection('chats').doc(chatId).collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots();
  }

  String _time(Timestamp? t) {
    if (t == null) return '';
    final d = t.toDate();
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final m = d.minute.toString().padLeft(2, '0');
      return '$h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
    }
    return '${d.day}/${d.month}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userStream,
      builder: (context, userSnap) {
        if (!userSnap.hasData) {
          return const ListTile(leading: CircleAvatar(radius: 28, child: Icon(Icons.person)), title: Text("Loading..."));
        }
        final user = userSnap.data!.data();
        if (user == null) return const SizedBox.shrink();
        final name = (user['name'] as String?) ?? 'User';
        final photo = user['photoUrl'] as String?;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: lastMsgStream,
          builder: (context, msgSnap) {
            String preview = (user['bio'] as String?) ?? 'Say hello 👋';
            String time = '';
            bool mine = false;
            if (msgSnap.hasData && msgSnap.data!.docs.isNotEmpty) {
              final m = msgSnap.data!.docs.first.data();
              preview = (m['text'] as String?) ?? '';
              mine = m['senderId'] == widget.myUid;
              final ts = m['timestamp'];
              time = _time(ts is Timestamp ? ts : null);
            }
            return Material(
              color: Colors.white,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => UserProfileScreen(uid: widget.otherUid)),
                  ),
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.grey[300],
                        backgroundImage: photo != null ? NetworkImage(photo) : null,
                        child: photo == null ? const Icon(Icons.person, color: Colors.white) : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: PresenceDot(online: isOnlineNow(user), size: 14),
                      ),
                    ],
                  ),
                ),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  mine ? 'You: $preview' : preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[700]),
                ),
                trailing: Text(time, style: TextStyle(fontSize: 12, color: kWaHeaderColor)),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ChatScreen(otherUid: widget.otherUid, otherName: name)),
                ),
                onLongPress: () => confirmAndUnmatch(context, widget.otherUid, name),
              ),
            );
          },
        );
      },
    );
  }
}
