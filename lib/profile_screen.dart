import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'search_screen.dart';
import 'main_shell.dart';
import 'main.dart';
import 'user_utils.dart';
import 'profile_details_card.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final nameCtrl = TextEditingController();
  final usernameCtrl = TextEditingController();
  final bioCtrl = TextEditingController();
  final interestsCtrl = TextEditingController();
  final locationCtrl = TextEditingController();
  String? gender;
  File? pickedImage;
  bool saving = false;
  String message = "";
  String? claimedUsername; // remembers a username already reserved by an earlier failed attempt

  // Details the user already entered during registration
  Map<String, dynamic> userData = {};
  bool loadingData = true;

  @override
  void initState() {
    super.initState();
    loadExisting();
  }

  /// Pre-fills this screen with what was entered at registration,
  /// so the user isn't asked again and nothing gets overwritten with blanks.
  Future<void> loadExisting() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final d = doc.data() ?? <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        userData = d;
        nameCtrl.text = (d['name'] ?? '').toString();
        bioCtrl.text = (d['bio'] ?? '').toString();
        locationCtrl.text = (d['location'] ?? d['city'] ?? '').toString();
        interestsCtrl.text = d['interests'] is List ? (d['interests'] as List).join(', ') : '';
        final g = d['gender']?.toString();
        if (g != null && kGenders.contains(g)) gender = g;
        loadingData = false;
      });
    } catch (_) {
      if (mounted) setState(() => loadingData = false);
    }
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1080);
    if (picked != null) {
      setState(() => pickedImage = File(picked.path));
    }
  }

  Future<void> saveProfile() async {
    if (nameCtrl.text.trim().isEmpty) {
      setState(() => message = "Please enter your name.");
      return;
    }
    final usernameError = validateUsername(usernameCtrl.text);
    if (usernameError != null) {
      setState(() => message = usernameError);
      return;
    }
    if (gender == null) {
      setState(() => message = "Please select your gender.");
      return;
    }

    setState(() { saving = true; message = ""; });
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // 1) reserve the unique username
      final claimError = await claimUsername(
        uid: uid,
        newUsername: usernameCtrl.text,
        oldUsername: claimedUsername,
      );
      if (claimError != null) {
        setState(() => message = claimError);
        return;
      }
      claimedUsername = normalizeUsername(usernameCtrl.text);

      // 2) upload photo (errors are shown, not swallowed)
      String? photoUrl;
      if (pickedImage != null) {
        try {
          photoUrl = await uploadProfilePhoto(pickedImage!, uid, '${DateTime.now().millisecondsSinceEpoch}.jpg');
        } catch (e) {
          setState(() => message = "Photo upload failed: $e\n\nCheck your Cloudinary cloud name / preset in user_utils.dart, or tap 'Remove photo' to continue without one.");
          return;
        }
      }

      // 3) save the profile
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'name': nameCtrl.text.trim(),
        'username': normalizeUsername(usernameCtrl.text),
        'gender': gender,
        'location': locationCtrl.text.trim(),
        'city': locationCtrl.text.trim(),
        'bio': bioCtrl.text.trim(),
        'interests': interestsCtrl.text.trim().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (photoUrl != null) 'photos': [photoUrl],
        'profileComplete': true,
      });

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainShell()));
      }
    } catch (e) {
      setState(() => message = "Error: $e");
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Set up your profile"),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: logout,
          ),
        ],
      ),
      body: loadingData ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: pickImage,
                child: Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                    image: pickedImage != null
                        ? DecorationImage(image: FileImage(pickedImage!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: pickedImage == null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.add_a_photo_outlined, size: 36, color: Colors.grey),
                              SizedBox(height: 6),
                              Text("Tap to add a profile photo"),
                            ],
                          ),
                        )
                      : null,
                ),
              ),
              if (pickedImage != null)
                TextButton(
                  onPressed: () => setState(() => pickedImage = null),
                  child: const Text("Remove photo"),
                ),
              const SizedBox(height: 18),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Your name", border: OutlineInputBorder())),
              const SizedBox(height: 14),
              TextField(
                controller: usernameCtrl,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: "Username",
                  prefixText: "@",
                  helperText: "3-20 characters: letters, numbers, . and _",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: gender,
                decoration: const InputDecoration(labelText: "Gender", border: OutlineInputBorder()),
                items: kGenders.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (v) => setState(() => gender = v),
              ),
              const SizedBox(height: 14),
              TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: "Location / city", border: OutlineInputBorder())),
              const SizedBox(height: 14),
              TextField(controller: bioCtrl, maxLines: 3, decoration: const InputDecoration(labelText: "Short bio", border: OutlineInputBorder())),
              const SizedBox(height: 14),
              TextField(controller: interestsCtrl, decoration: const InputDecoration(labelText: "Interests (comma separated)", hintText: "e.g. books, travel, cooking", border: OutlineInputBorder())),
              if (userData.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text("Your details", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ProfileDetailsCard(data: userData, showAbout: false),
              ],
              const SizedBox(height: 20),
              if (saving) const Center(child: CircularProgressIndicator()) else
                ElevatedButton(onPressed: saveProfile, child: const Text("Save Profile")),
              const SizedBox(height: 12),
              Text(message, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ),
    );
  }
}