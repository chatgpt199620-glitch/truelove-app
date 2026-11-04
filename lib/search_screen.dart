import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_profile_screen.dart';
import 'user_utils.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final searchCtrl = TextEditingController();
  List<Map<String, dynamic>> results = [];
  bool loading = false;
  Set<String> blockedByMe = {};

  Future<void> loadBlockedList() async {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseFirestore.instance.collection('users').doc(myUid).collection('blocked').get();
    blockedByMe = snap.docs.map((d) => d.id).toSet();
  }

  Future<void> searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() => results = []);
      return;
    }
    setState(() => loading = true);
    await loadBlockedList();
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('profileComplete', isEqualTo: true)
        .orderBy('name')
        .startAt([query])
        .endAt(['$query\uf8ff'])
        .limit(20)
        .get();

    final filtered = snap.docs
        .where((d) => d.id != myUid && !blockedByMe.contains(d.id))
        .map((d) => {'uid': d.id, ...d.data()})
        .toList();

    if (!mounted) return;
    setState(() {
      results = filtered;
      loading = false;
    });
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: searchCtrl,
          // autofocus off: this screen now lives inside a tab
          decoration: InputDecoration(
            hintText: "Search by name...",
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.grey[100],
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
          ),
          style: const TextStyle(fontSize: 16),
          onChanged: searchUsers,
        ),
      ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : results.isEmpty
                ? Center(
                    child: Text(
                      searchCtrl.text.isEmpty ? "Start typing a name to search" : "No users found",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final user = results[i];
                      final age = ageFromDob(user['dob']);
                      final loc = (user['location'] as String?) ?? '';
                      final name = user['name'] ?? 'Unknown';
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        child: ListTile(
                          leading: CircleAvatar(
                            radius: 26,
                            backgroundImage: user['photoUrl'] != null ? NetworkImage(user['photoUrl']) : null,
                            child: user['photoUrl'] == null ? const Icon(Icons.person) : null,
                          ),
                          title: Text(age != null ? "$name, $age" : name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            [if (loc.isNotEmpty) loc, if ((user['bio'] ?? '').toString().isNotEmpty) user['bio']].join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => UserProfileScreen(uid: user['uid'])),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
