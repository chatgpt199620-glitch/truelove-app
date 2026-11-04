import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_profile_screen.dart';
import 'user_utils.dart';

typedef _Snap = QuerySnapshot<Map<String, dynamic>>;
typedef _Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  late final String myUid;
  late final Stream<_Snap> receivedStream;
  late final Stream<_Snap> sentStream;
  String myName = 'Someone';

  @override
  void initState() {
    super.initState();
    myUid = FirebaseAuth.instance.currentUser!.uid;
    final col = FirebaseFirestore.instance.collection('requests');
    // Single-field equality queries only => NO composite index needed.
    // Sorting and status filtering are done in the app instead.
    receivedStream = col.where('to', isEqualTo: myUid).snapshots();
    sentStream = col.where('from', isEqualTo: myUid).snapshots();
    FirebaseFirestore.instance.collection('users').doc(myUid).get().then((d) {
      if (mounted) setState(() => myName = d.data()?['name'] ?? 'Someone');
    });
  }

  Future<void> acceptRequest(BuildContext context, String requestId, String fromUid, String myUid, String myName) async {
    try {
      // one atomic batch: request status + match + notification
      await RequestService.accept(fromUid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request accepted! You're now connected.")));
      }
    } catch (e) {
      // errors are now visible instead of silently leaving the request "pending"
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Accept failed: $e")));
      }
    }
  }

  Future<void> declineRequest(String requestId) async {
    try {
      await FirebaseFirestore.instance.collection('requests').doc(requestId).update({'status': 'declined'});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Decline failed: $e")));
      }
    }
  }

  Future<void> cancelRequest(String requestId) async {
    await FirebaseFirestore.instance.collection('requests').doc(requestId).delete();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request cancelled")));
    }
  }

  /// Pending first, then newest first.
  List<_Doc> sorted(List<_Doc> docs) {
    final list = [...docs];
    int rank(String? s) => s == 'pending' ? 0 : 1;
    int millis(Map<String, dynamic> d) {
      final t = d['timestamp'];
      // a just-created request has no server timestamp yet => treat as newest
      return t is Timestamp ? t.millisecondsSinceEpoch : DateTime.now().millisecondsSinceEpoch;
    }
    list.sort((a, b) {
      final da = a.data();
      final db = b.data();
      final r = rank(da['status'] as String?) - rank(db['status'] as String?);
      if (r != 0) return r;
      return millis(db).compareTo(millis(da));
    });
    return list;
  }

  int countStatus(List<_Doc> docs, String status) =>
      docs.where((d) => d.data()['status'] == status).length;

  Widget errorView(Object error) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 40),
          const SizedBox(height: 12),
          const Text(
            "Couldn't load requests. If this says 'permission-denied', update your Firestore rules to allow reading "
            "requests where you are the sender or receiver.",
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(error.toString(), style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget statCard(String label, int value, Color color, IconData icon) {
    return Expanded(
      child: Card(
        elevation: 0,
        color: color.withOpacity(0.10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text('$value', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget dashboard(List<_Doc> received, List<_Doc> sent) {
    final pending = countStatus(received, 'pending') + countStatus(sent, 'pending');
    final accepted = countStatus(received, 'accepted') + countStatus(sent, 'accepted');
    final declined = countStatus(received, 'declined') + countStatus(sent, 'declined');
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          statCard("Sent", sent.length, Colors.blue, Icons.north_east),
          statCard("Received", received.length, Colors.purple, Icons.south_west),
          statCard("Pending", pending, Colors.orange, Icons.hourglass_bottom),
          statCard("Accepted", accepted, Colors.green, Icons.check_circle_outline),
          statCard("Declined", declined, Colors.red, Icons.cancel_outlined),
        ],
      ),
    );
  }

  Widget buildList(List<_Doc> docs, {required bool received}) {
    if (docs.isEmpty) {
      return Center(child: Text(received ? "No requests received yet" : "You haven't sent any requests yet"));
    }
    return ListView.builder(
      itemCount: docs.length,
      itemBuilder: (context, i) {
        final data = docs[i].data();
        final requestId = docs[i].id;
        final otherUid = (received ? data['from'] : data['to']) as String;
        final status = (data['status'] as String?) ?? 'pending';
        return _RequestTile(
          key: ValueKey(requestId),
          otherUid: otherUid,
          status: status,
          received: received,
          onAccept: () => acceptRequest(context, requestId, otherUid, myUid, myName),
          onDecline: () => declineRequest(requestId),
          onCancel: () => cancelRequest(requestId),
        );
      },
    );
  }

  /// "Accepted" tab: accepted requests in BOTH directions (sent by me or received by me).
  Widget buildAcceptedList(List<_Doc> received, List<_Doc> sent) {
    final all = <_Doc>[
      ...received.where((d) => d.data()['status'] == 'accepted'),
      ...sent.where((d) => d.data()['status'] == 'accepted'),
    ];
    if (all.isEmpty) {
      return const Center(child: Text("No accepted requests yet"));
    }
    final seen = <String>{};
    final tiles = <Widget>[];
    for (final d in all) {
      final data = d.data();
      final otherUid = (data['from'] == myUid ? data['to'] : data['from']) as String;
      if (!seen.add(otherUid)) continue; // avoid duplicates if both directions exist
      tiles.add(_RequestTile(
        key: ValueKey('accepted_${d.id}'),
        otherUid: otherUid,
        status: 'accepted',
        received: data['to'] == myUid,
        onAccept: () {},
        onDecline: () {},
        onCancel: () {},
      ));
    }
    return ListView(children: tiles);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<_Snap>(
      stream: receivedStream,
      builder: (context, recvSnap) {
        return StreamBuilder<_Snap>(
          stream: sentStream,
          builder: (context, sentSnap) {
            if (recvSnap.hasError) return Scaffold(appBar: AppBar(title: const Text("Requests")), body: errorView(recvSnap.error!));
            if (sentSnap.hasError) return Scaffold(appBar: AppBar(title: const Text("Requests")), body: errorView(sentSnap.error!));
            if (!recvSnap.hasData || !sentSnap.hasData) {
              return Scaffold(appBar: AppBar(title: const Text("Requests")), body: const Center(child: CircularProgressIndicator()));
            }

            final received = sorted(recvSnap.data!.docs);
            final sent = sorted(sentSnap.data!.docs);
            final pendingReceived = countStatus(received, 'pending');

            return DefaultTabController(
              length: 3,
              child: Scaffold(
                appBar: AppBar(
                  title: const Text("Requests"),
                  bottom: TabBar(
                    tabs: [
                      Tab(text: pendingReceived > 0 ? "Received ($pendingReceived new)" : "Received"),
                      const Tab(text: "Sent"),
                      const Tab(text: "Accepted"),
                    ],
                  ),
                ),
                body: Column(
                  children: [
                    dashboard(received, sent),
                    const SizedBox(height: 4),
                    Expanded(
                      child: TabBarView(
                        children: [
                          buildList(received, received: true),
                          buildList(sent, received: false),
                          buildAcceptedList(received, sent),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _RequestTile extends StatefulWidget {
  final String otherUid;
  final String status;
  final bool received;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onCancel;

  const _RequestTile({
    super.key,
    required this.otherUid,
    required this.status,
    required this.received,
    required this.onAccept,
    required this.onDecline,
    required this.onCancel,
  });

  @override
  State<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends State<_RequestTile> {
  late final Future<DocumentSnapshot<Map<String, dynamic>>> userFuture;

  @override
  void initState() {
    super.initState();
    // fetched once per tile, so live status changes don't re-download the user
    userFuture = FirebaseFirestore.instance.collection('users').doc(widget.otherUid).get();
  }

  Widget statusChip(String status) {
    final Color c = status == 'accepted' ? Colors.green : status == 'declined' ? Colors.red : Colors.orange;
    final String label = status == 'accepted' ? 'Accepted' : status == 'declined' ? 'Declined' : 'Pending';
    return Chip(
      label: Text(label, style: TextStyle(color: c, fontSize: 12)),
      backgroundColor: c.withOpacity(0.1),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget? trailing() {
    if (widget.status == 'pending') {
      if (widget.received) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.check_circle, color: Colors.green), onPressed: widget.onAccept),
            IconButton(icon: const Icon(Icons.cancel, color: Colors.red), onPressed: widget.onDecline),
          ],
        );
      }
      return TextButton(onPressed: widget.onCancel, child: const Text("Cancel"));
    }
    return statusChip(widget.status);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: userFuture,
      builder: (context, userSnap) {
        if (!userSnap.hasData) {
          return const ListTile(leading: CircleAvatar(child: Icon(Icons.person)), title: Text("Loading..."));
        }
        final user = userSnap.data!.data();
        if (user == null) {
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_off)),
            title: const Text("Deleted user"),
            trailing: trailing(),
          );
        }
        final username = user['username'] as String?;
        final bio = (user['bio'] as String?) ?? '';
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: user['photoUrl'] != null ? NetworkImage(user['photoUrl']) : null,
            child: user['photoUrl'] == null ? const Icon(Icons.person) : null,
          ),
          title: Text(user['name'] ?? 'Unknown'),
          subtitle: Text(
            [if (username != null && username.isNotEmpty) '@$username', if (bio.isNotEmpty) bio].join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: trailing(),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => UserProfileScreen(uid: widget.otherUid)),
          ),
        );
      },
    );
  }
}
