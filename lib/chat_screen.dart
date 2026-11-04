import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'call_screen.dart';
import 'main.dart';
import 'user_profile_screen.dart';
import 'presence_service.dart';
import 'unmatch_helper.dart';
import 'user_utils.dart';
import 'whatsapp_theme.dart';

class ChatScreen extends StatefulWidget {
  final String otherUid;
  final String otherName;
  const ChatScreen({super.key, required this.otherUid, required this.otherName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final msgCtrl = TextEditingController();
  late final String chatId;
  late final String myUid;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> matchStream;
  bool connected = true;

  final List<String> scamKeywords = [
    'bitcoin', 'crypto', 'investment', 'western union', 'gift card',
    'send money', 'bank transfer', 'loan', 'upi', 'paytm', 'otp',
    'emergency', 'customs fee', 'processing fee'
  ];

  final List<String> abusiveKeywords = [
    'bastard', 'bitch', 'slut', 'whore', 'rape', 'kill you', 'bc', 'mc',
    'chutiya', 'madarchod', 'behenchod', 'randi', 'harami',
  ];

  @override
  void initState() {
    super.initState();
    myUid = FirebaseAuth.instance.currentUser!.uid;
    chatId = ([myUid, widget.otherUid]..sort()).join('_');
    matchStream = FirebaseFirestore.instance
        .collection('matches')
        .where('users', arrayContains: myUid)
        .snapshots();
  }

  @override
  void dispose() {
    msgCtrl.dispose();
    super.dispose();
  }

  bool looksLikeScam(String text) {
    final lower = text.toLowerCase();
    return scamKeywords.any((w) => lower.contains(w));
  }

  bool looksAbusive(String text) {
    final lower = text.toLowerCase();
    return abusiveKeywords.any((w) => lower.contains(w));
  }

  Future<void> suspendMyAccount(String reason) async {
    await FirebaseFirestore.instance.collection('users').doc(myUid).update({
      'isBanned': true,
      'banReason': reason,
      'bannedAt': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance.collection('violations').add({
      'uid': myUid,
      'reason': reason,
      'chatId': chatId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await FirebaseAuth.instance.signOut();

    if (mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text("Account Suspended"),
          content: const Text(
              "Your account has been permanently suspended for violating our community guidelines "
              "(abusive or vulgar language). You will not be able to log in again."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const StartupGate()), (route) => false);
              },
              child: const Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  Future<void> sendMessage() async {
    final text = msgCtrl.text.trim();
    if (text.isEmpty) return;
    if (!connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're no longer connected, so you can't send messages.")),
      );
      return;
    }

    if (looksAbusive(text)) {
      await suspendMyAccount('Abusive/vulgar language detected in chat');
      return;
    }

    if (looksLikeScam(text)) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("⚠️ Be careful"),
          content: const Text(
              "This message mentions money or financial details. Never send money, OTPs, or banking info to someone you've met on this app. Report this chat if asked for money."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Send anyway")),
          ],
        ),
      );
      if (proceed != true) return;
    }

    await FirebaseFirestore.instance.collection('chats').doc(chatId).collection('messages').add({
      'text': text,
      'senderId': myUid,
      'timestamp': FieldValue.serverTimestamp(),
    });
    msgCtrl.clear();
  }

  Future<void> reportUser() async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Report user"),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(hintText: "Why are you reporting this person?"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, reasonCtrl.text), child: const Text("Submit")),
        ],
      ),
    );
    if (reason != null && reason.trim().isNotEmpty) {
      await FirebaseFirestore.instance.collection('reports').add({
        'reportedUid': widget.otherUid,
        'reportedBy': myUid,
        'reason': reason.trim(),
        'chatId': chatId,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Report submitted. Thank you.")));
      }
    }
  }

  Future<void> blockUser() async {
    await FirebaseFirestore.instance
        .collection('users').doc(myUid)
        .collection('blocked').doc(widget.otherUid)
        .set({'timestamp': FieldValue.serverTimestamp()});
    try {
      await RequestService.unmatch(widget.otherUid);
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${widget.otherName} has been blocked.")));
      Navigator.pop(context);
    }
  }

  Future<void> unmatchUser() async {
    final done = await confirmAndUnmatch(context, widget.otherUid, widget.otherName);
    if (done && mounted) Navigator.pop(context);
  }

  void startCall(bool isVideo) {
    final channelName = chatId;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CallScreen(channelName: channelName, isVideoCall: isVideo, otherName: widget.otherName),
    ));
  }

  String _time(dynamic ts) {
    if (ts is! Timestamp) return '';
    final d = ts.toDate();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: matchStream,
      builder: (context, matchSnap) {
        if (matchSnap.hasData) {
          connected = matchSnap.data!.docs.any((d) => d.id == chatId);
        }
        return Scaffold(
      backgroundColor: kWaChatBg,
      appBar: AppBar(
        backgroundColor: kWaHeaderColor,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => UserProfileScreen(uid: widget.otherUid)),
          ),
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('users').doc(widget.otherUid).snapshots(),
            builder: (context, snap) {
              final u = snap.data?.data();
              final photo = u?['photoUrl'] as String?;
              final online = isOnlineNow(u);
              final status = presenceText(u);
              return Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.grey[300],
                        backgroundImage: photo != null ? NetworkImage(photo) : null,
                        child: photo == null ? const Icon(Icons.person, size: 18, color: Colors.white) : null,
                      ),
                      Positioned(right: 0, bottom: 0, child: PresenceDot(online: online, size: 11)),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.otherName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, color: Colors.white)),
                        if (status.isNotEmpty)
                          Text(
                            status,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.normal,
                              color: online ? Colors.greenAccent : Colors.white70,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          if (connected) IconButton(icon: const Icon(Icons.call_outlined), onPressed: () => startCall(false)),
          if (connected) IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: () => startCall(true)),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'report') reportUser();
              if (value == 'block') blockUser();
              if (value == 'unmatch') unmatchUser();
            },
            itemBuilder: (_) => [
              if (connected) const PopupMenuItem(value: 'unmatch', child: Text('Unmatch')),
              const PopupMenuItem(value: 'report', child: Text('Report')),
              const PopupMenuItem(value: 'block', child: Text('Block')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: Colors.amber[100],
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: const Text(
                "⚠️ Never send money, gift cards, or OTPs. Abusive language leads to permanent suspension.",
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('chats').doc(chatId).collection('messages')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return Center(
                      child: Text("Say hello to ${widget.otherName} 👋", style: TextStyle(color: Colors.grey[600])),
                    );
                  }
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      final isMe = data['senderId'] == myUid;
                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.fromLTRB(14, 9, 14, 6),
                            decoration: BoxDecoration(
                              color: isMe ? kWaBubbleSent : kWaBubbleReceived,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(isMe ? 16 : 4),
                                bottomRight: Radius.circular(isMe ? 4 : 16),
                              ),
                              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  data['text'] ?? '',
                                  style: const TextStyle(fontSize: 15, color: Colors.black87),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _time(data['timestamp']),
                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            if (!connected)
              Container(
                width: double.infinity,
                color: Colors.grey[200],
                padding: const EdgeInsets.all(16),
                child: Text(
                  "You're no longer connected with ${widget.otherName}. Messaging is turned off.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[700]),
                ),
              )
            else
            Container(
              color: kWaChatBg,
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: msgCtrl,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: "Type a message",
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  CircleAvatar(
                    backgroundColor: kWaAccentColor,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}
