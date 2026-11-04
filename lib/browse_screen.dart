import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_utils.dart';
import 'user_profile_screen.dart';
import 'presence_service.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});
  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  List<Map<String, dynamic>> profiles = [];
  Set<String> blockedUids = {};
  Set<String> alreadyRequested = {};
  Set<String> incomingRequests = {}; // people who sent ME a pending request
  bool loading = true;
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    loadProfiles();
  }

  Future<void> loadProfiles() async {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    final blockedSnap = await FirebaseFirestore.instance
        .collection('users').doc(myUid).collection('blocked').get();
    blockedUids = blockedSnap.docs.map((d) => d.id).toSet();

    final sentSnap = await FirebaseFirestore.instance
        .collection('requests').where('from', isEqualTo: myUid).where('status', isEqualTo: 'pending').get();
    alreadyRequested = sentSnap.docs.map((d) => d['to'] as String).toSet();

    final recvSnap = await FirebaseFirestore.instance
        .collection('requests').where('to', isEqualTo: myUid).where('status', isEqualTo: 'pending').get();
    incomingRequests = recvSnap.docs.map((d) => d['from'] as String).toSet();

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('profileComplete', isEqualTo: true)
        .limit(50)
        .get();

    final filtered = snap.docs
        .where((d) => d.id != myUid && !blockedUids.contains(d.id))
        .map((d) => {'uid': d.id, ...d.data()})
        .toList();

    // People who already sent you a request are shown first
    filtered.sort((a, b) {
      final ra = incomingRequests.contains(a['uid']) ? 0 : 1;
      final rb = incomingRequests.contains(b['uid']) ? 0 : 1;
      return ra.compareTo(rb);
    });

    if (!mounted) return;
    setState(() {
      profiles = filtered;
      loading = false;
    });
  }

  Future<void> sendRequest(String otherUid) async {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    final otherName = profiles[currentIndex]['name'] ?? 'User';

    final myDoc = await FirebaseFirestore.instance.collection('users').doc(myUid).get();
    final myName = myDoc.data()?['name'] ?? 'Someone';

    await FirebaseFirestore.instance.collection('requests').doc('${myUid}_$otherUid').set({
      'from': myUid,
      'to': otherUid,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance
        .collection('users').doc(otherUid).collection('notifications').add({
      'type': 'request',
      'text': '$myName sent you a connection request',
      'fromUid': myUid,
      'read': false,
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Request sent to $otherName")));
    }

    setState(() {
      alreadyRequested.add(otherUid);
      currentIndex++;
    });
  }

  Future<void> cancelRequest(String otherUid) async {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance.collection('requests').doc('${myUid}_$otherUid').delete();
    setState(() => alreadyRequested.remove(otherUid));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request cancelled")));
    }
  }

  Future<void> acceptIncoming(String otherUid, String otherName) async {
    try {
      await RequestService.accept(otherUid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("You're now connected with $otherName!")));
      setState(() {
        incomingRequests.remove(otherUid);
        currentIndex++;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Accept failed: $e")));
    }
  }

  Future<void> declineIncoming(String otherUid) async {
    try {
      await RequestService.decline(otherUid);
      if (!mounted) return;
      setState(() {
        incomingRequests.remove(otherUid);
        currentIndex++;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Decline failed: $e")));
    }
  }

  void passProfile() {
    setState(() => currentIndex++);
  }

  Widget _roundButton({required IconData icon, required Color color, required VoidCallback onTap, String? tooltip}) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Tooltip(message: tooltip ?? '', child: Icon(icon, color: color, size: 28)),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (currentIndex >= profiles.length) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_border, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 12),
              const Text("No more profiles right now", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text("Check back later!", style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(160, 44)),
                icon: const Icon(Icons.refresh),
                label: const Text("Refresh"),
                onPressed: () {
                  setState(() {
                    loading = true;
                    currentIndex = 0;
                  });
                  loadProfiles();
                },
              ),
            ],
          ),
        ),
      );
    }

    final profile = profiles[currentIndex];
    final interests = (profile['interests'] as List?)?.cast<String>() ?? [];
    final alreadySent = alreadyRequested.contains(profile['uid']);
    final hasIncoming = incomingRequests.contains(profile['uid']);
    final photos = photosOf(profile);
    final age = ageFromDob(profile['dob']);
    final name = (profile['name'] as String?) ?? 'Unknown';
    final location = (profile['location'] as String?) ?? '';
    final gender = (profile['gender'] as String?) ?? '';
    final username = (profile['username'] as String?) ?? '';
    final bio = (profile['bio'] as String?) ?? '';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => UserProfileScreen(uid: profile['uid'])),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      photos.isEmpty
                          ? Container(color: Colors.grey[300], child: const Icon(Icons.person, size: 100, color: Colors.white))
                          : Image.network(
                              photos.first,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(color: Colors.grey[300], child: const Icon(Icons.broken_image, size: 60, color: Colors.grey)),
                            ),
                      // dark gradient so text is readable
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.center,
                            colors: [Color(0xCC000000), Colors.transparent],
                          ),
                        ),
                      ),
                      if (hasIncoming)
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(20)),
                            child: const Text("Interested in you", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      if (photos.length > 1)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.photo_library_outlined, size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Text('${photos.length}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              age != null ? "$name, $age" : name,
                              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                            ),
                            if (username.isNotEmpty)
                              Text("@$username", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (location.isNotEmpty) _infoChip(Icons.location_on_outlined, location),
                                if (gender.isNotEmpty) _infoChip(Icons.person_outline, gender),
                                if (presenceText(profile).isNotEmpty)
                                  _infoChip(
                                    isOnlineNow(profile) ? Icons.circle : Icons.access_time,
                                    presenceText(profile),
                                  ),
                              ],
                            ),
                            if (bio.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(bio, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, height: 1.3)),
                            ],
                            if (interests.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: interests.take(4).map((i) => _infoChip(Icons.tag, i)).toList(),
                              ),
                            ],
                            const SizedBox(height: 4),
                            const Text("Tap to view full profile", style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (hasIncoming) ...[
              Text("$name sent you a request", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      icon: const Icon(Icons.check),
                      label: const Text("Accept"),
                      onPressed: () => acceptIncoming(profile['uid'], name),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close, color: Colors.red),
                      label: const Text("Decline"),
                      onPressed: () => declineIncoming(profile['uid']),
                    ),
                  ),
                ],
              ),
            ] else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _roundButton(icon: Icons.close, color: Colors.redAccent, tooltip: "Skip", onTap: passProfile),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: alreadySent ? Colors.grey : Colors.pinkAccent,
                          foregroundColor: Colors.white,
                        ),
                        icon: Icon(alreadySent ? Icons.close : Icons.favorite),
                        label: Text(alreadySent ? "Cancel Request" : "Send Request"),
                        onPressed: alreadySent ? () => cancelRequest(profile['uid']) : () => sendRequest(profile['uid']),
                      ),
                    ),
                  ),
                  _roundButton(
                    icon: Icons.person_search_outlined,
                    color: Colors.blue,
                    tooltip: "View profile",
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => UserProfileScreen(uid: profile['uid'])),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
