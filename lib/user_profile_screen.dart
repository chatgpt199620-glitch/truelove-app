import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_utils.dart';
import 'chat_screen.dart';
import 'presence_service.dart';
import 'edit_photo_screen.dart';
import 'unmatch_helper.dart';
import 'profile_details_card.dart';

/// Shows another user's full profile. Open it with:
/// Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(uid: someUid)));
class UserProfileScreen extends StatefulWidget {
  final String uid;
  const UserProfileScreen({super.key, required this.uid});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final PageController pageCtrl = PageController();
  int page = 0;
  bool busy = false;

  late final String myUid;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> userStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> sentStream; // me -> them
  late final Stream<QuerySnapshot<Map<String, dynamic>>> recvStream; // them -> me

  @override
  void initState() {
    super.initState();
    myUid = FirebaseAuth.instance.currentUser!.uid;
    final db = FirebaseFirestore.instance;
    userStream = db.collection('users').doc(widget.uid).snapshots();
    sentStream = db
        .collection('requests')
        .where('from', isEqualTo: myUid)
        .where('to', isEqualTo: widget.uid)
        .snapshots();
    recvStream = db
        .collection('requests')
        .where('from', isEqualTo: widget.uid)
        .where('to', isEqualTo: myUid)
        .snapshots();
  }

  @override
  void dispose() {
    pageCtrl.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action, String doneMessage) async {
    setState(() => busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(doneMessage)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Something went wrong: $e")));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String? statusOf(AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
    if (!snap.hasData || snap.data!.docs.isEmpty) return null;
    return snap.data!.docs.first.data()['status'] as String?;
  }

  Widget buildActions(String otherName) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: sentStream,
      builder: (context, sentSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: recvStream,
          builder: (context, recvSnap) {
            final sent = statusOf(sentSnap); // my request to them
            final recv = statusOf(recvSnap); // their request to me

            if (busy) return const Center(child: CircularProgressIndicator());

            if (sent == 'accepted' || recv == 'accepted') {
              return Column(
                children: [
                  const Text("✅ You're connected", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      icon: const Icon(Icons.chat),
                      label: const Text("Message"),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ChatScreen(otherUid: widget.uid, otherName: otherName)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.link_off, color: Colors.red),
                      label: const Text("Unmatch", style: TextStyle(color: Colors.red)),
                      onPressed: () => confirmAndUnmatch(context, widget.uid, otherName),
                    ),
                  ),
                ],
              );
            }

            if (recv == 'pending') {
              return Column(
                children: [
                  Text("$otherName sent you a request",
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                          icon: const Icon(Icons.check),
                          label: const Text("Accept"),
                          onPressed: () => run(() => RequestService.accept(widget.uid), "Request accepted!"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.close, color: Colors.red),
                          label: const Text("Decline"),
                          onPressed: () => run(() => RequestService.decline(widget.uid), "Request declined"),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }

            if (sent == 'pending') {
              return Column(
                children: [
                  const Text("Request sent — waiting for a reply", style: TextStyle(color: Colors.orange)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close),
                      label: const Text("Cancel request"),
                      onPressed: () => run(() => RequestService.cancel(widget.uid), "Request cancelled"),
                    ),
                  ),
                ],
              );
            }

            if (sent == 'declined') {
              return const Text("Your request was declined.", style: TextStyle(color: Colors.red));
            }

            return Column(
              children: [
                if (recv == 'declined')
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text("You declined this person's earlier request.", style: TextStyle(color: Colors.grey)),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent, foregroundColor: Colors.white),
                    icon: const Icon(Icons.favorite),
                    label: const Text("Send Request"),
                    onPressed: () => run(() => RequestService.send(widget.uid), "Request sent to $otherName"),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMe = widget.uid == myUid;

    return Scaffold(
      appBar: AppBar(title: Text(isMe ? "My Profile" : "Profile")),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userStream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text("Couldn't load profile: ${snap.error}")));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final data = snap.data!.data();
          if (data == null) return const Center(child: Text("This user no longer exists."));

          final photos = photosOf(data);
          final name = (data['name'] as String?)?.trim().isNotEmpty == true ? data['name'] as String : 'Unknown';
          final username = data['username'] as String?;
          final nickname = data['nickname'] as String?;
          final age = ageFromDob(data['dob']);
          final gender = data['gender'] as String?;
          final location = data['location'] as String?;
          final bio = data['bio'] as String? ?? '';
          final interests = (data['interests'] as List?)?.cast<String>() ?? [];

          return ListView(
            children: [
              SizedBox(
                height: 400,
                child: photos.isEmpty
                    ? Container(color: Colors.grey[300], child: const Center(child: Icon(Icons.person, size: 90, color: Colors.grey)))
                    : Stack(
                        children: [
                          PageView.builder(
                            controller: pageCtrl,
                            itemCount: photos.length,
                            onPageChanged: (i) => setState(() => page = i),
                            itemBuilder: (_, i) => Image.network(
                              photos[i],
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey[300],
                                child: const Center(child: Icon(Icons.broken_image, size: 60, color: Colors.grey)),
                              ),
                            ),
                          ),
                          if (photos.length > 1)
                            Positioned(
                              bottom: 10,
                              left: 0,
                              right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  photos.length,
                                  (i) => Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 3),
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: i == page ? Colors.white : Colors.white54,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(age != null ? "$name, $age" : name,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                    if (username != null && username.isNotEmpty)
                      Text("@$username", style: const TextStyle(fontSize: 16, color: Colors.red)),
                    if (nickname != null && nickname.isNotEmpty)
                      Text("Nickname: $nickname", style: const TextStyle(color: Colors.grey)),
                    if (!isMe && presenceText(data).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            PresenceDot(online: isOnlineNow(data), size: 12),
                            const SizedBox(width: 6),
                            Text(
                              presenceText(data),
                              style: TextStyle(
                                fontSize: 13,
                                color: isOnlineNow(data) ? Colors.green : Colors.grey[600],
                                fontWeight: isOnlineNow(data) ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (gender != null && gender.isNotEmpty)
                          Chip(avatar: const Icon(Icons.person_outline, size: 16), label: Text(gender)),
                        if (location != null && location.isNotEmpty)
                          Chip(avatar: const Icon(Icons.location_on_outlined, size: 16), label: Text(location)),
                      ],
                    ),
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text("About", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(bio, style: const TextStyle(fontSize: 15, height: 1.4)),
                    ],
                    if (interests.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text("Interests", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: interests.map((i) => Chip(label: Text(i, style: const TextStyle(fontSize: 12)))).toList(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Details entered at registration (relationship status, looking for, height, education, ...)
                    ProfileDetailsCard(data: data, showAbout: false),
                    const SizedBox(height: 12),
                    if (!isMe) buildActions(name),
                    if (isMe)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text("Edit photos / change profile picture"),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const EditPhotoScreen()),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}