import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'browse_screen.dart';
import 'requests_screen.dart';
import 'matches_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'notifications_screen.dart';
import 'presence_service.dart';
import 'whatsapp_theme.dart';
import 'animated_heart.dart';
import 'invite_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int currentTab = 0;
  Timer? _heartbeat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPresence();
  }

  void _startPresence() {
    PresenceService.goOnline();
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(minutes: 5), (_) => PresenceService.goOnline());
  }

  void _stopPresence() {
    _heartbeat?.cancel();
    _heartbeat = null;
    PresenceService.goOffline();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPresence();
    } else {
      _stopPresence();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPresence();
    super.dispose();
  }

  // Search is no longer a tab. It opens from the search icon in the top-right.
  // Tab order: 0 Matches, 1 Inbox, 2 Messages, 3 Settings, 4 Invite
  final screens = const [
    BrowseScreen(),
    RequestsScreen(),
    MatchesScreen(),
    SettingsScreen(),
    InviteScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final authUser = FirebaseAuth.instance.currentUser!;
    final myUid = authUser.uid;

    return Scaffold(
      appBar: currentTab == 0
          ? AppBar(
              backgroundColor: kWaHeaderColor,
              foregroundColor: Colors.white,
              toolbarHeight: 64,
              title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('users').doc(myUid).snapshots(),
                builder: (context, snap) {
                  final data = snap.data?.data();
                  final username = (data?['username'] as String?) ?? '';
                  final name = (data?['name'] as String?) ?? '';
                  final String loggedInAs = username.isNotEmpty
                      ? '@$username'
                      : name.isNotEmpty
                          ? name
                          : (authUser.email ?? authUser.phoneNumber ?? '');
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text("TrueLove", style: TextStyle(color: Colors.white)),
                          SizedBox(width: 4),
                          AnimatedHeart(size: 18, color: Colors.white, animation: HeartAnimation.jump),
                        ],
                      ),
                      if (loggedInAs.isNotEmpty)
                        Text(
                          "Logged in as $loggedInAs",
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.white70),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  );
                },
              ),
              actions: [
                // Search icon (top-right)
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Search',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SearchScreen()),
                  ),
                ),
                // Notifications icon with unread badge
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users').doc(myUid).collection('notifications')
                      .where('read', isEqualTo: false)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final count = snapshot.data?.docs.length ?? 0;
                    return IconButton(
                      icon: Badge(
                        isLabelVisible: count > 0,
                        label: Text('$count'),
                        child: const Icon(Icons.notifications_outlined),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                      ),
                    );
                  },
                ),
              ],
            )
          : null,
      body: IndexedStack(index: currentTab, children: screens),
      bottomNavigationBar: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('requests').where('to', isEqualTo: myUid).snapshots(),
        builder: (context, snap) {
          final pending = snap.data?.docs.where((d) => d.data()['status'] == 'pending').length ?? 0;
          return NavigationBar(
            backgroundColor: Colors.white,
            indicatorColor: kWaAccentColor.withOpacity(0.15),
            selectedIndex: currentTab,
            onDestinationSelected: (i) => setState(() => currentTab = i),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.favorite_border),
                selectedIcon: const Icon(Icons.favorite, color: kWaAccentColor),
                label: "Matches",
              ),
              NavigationDestination(
                icon: Badge(isLabelVisible: pending > 0, label: Text('$pending'), child: const Icon(Icons.inbox_outlined)),
                selectedIcon: const Icon(Icons.inbox, color: kWaAccentColor),
                label: "Inbox",
              ),
              NavigationDestination(
                icon: const Icon(Icons.chat_bubble_outline),
                selectedIcon: const Icon(Icons.chat_bubble, color: kWaAccentColor),
                label: "Messages",
              ),
              NavigationDestination(
                icon: const Icon(Icons.person_outline),
                selectedIcon: const Icon(Icons.person, color: kWaAccentColor),
                label: "Settings",
              ),
              NavigationDestination(
                icon: const Icon(Icons.share_outlined),
                selectedIcon: const Icon(Icons.share, color: kWaAccentColor),
                label: "Invite",
              ),
            ],
          );
        },
      ),
    );
  }
}
