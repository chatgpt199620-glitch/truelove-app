import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'user_utils.dart';

/// Add photos, choose which one is your profile picture, remove photos.
/// The FIRST photo in the list is the profile picture (photoUrl).
class EditPhotoScreen extends StatefulWidget {
  const EditPhotoScreen({super.key});
  @override
  State<EditPhotoScreen> createState() => _EditPhotoScreenState();
}

class _EditPhotoScreenState extends State<EditPhotoScreen> {
  static const int maxPhotos = 6;
  final String uid = FirebaseAuth.instance.currentUser!.uid;
  bool busy = false;

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save(List<String> photos) {
    return _ref.update({
      'photos': photos,
      'photoUrl': photos.isEmpty ? FieldValue.delete() : photos.first,
    });
  }

  Future<void> addPhoto(List<String> current) async {
    if (current.length >= maxPhotos) {
      _snack("You can add up to $maxPhotos photos.");
      return;
    }
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1080);
    if (picked == null) return;

    setState(() => busy = true);
    try {
      final url = await uploadProfilePhoto(File(picked.path), uid, '${DateTime.now().millisecondsSinceEpoch}.jpg');
      await _save([...current, url]); // first photo ever => becomes profile picture
      _snack(current.isEmpty ? "Profile picture set!" : "Photo added");
    } catch (e) {
      _snack("Upload failed: $e");
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> setAsProfile(List<String> photos, int index) async {
    setState(() => busy = true);
    try {
      final list = [...photos];
      final chosen = list.removeAt(index);
      await _save([chosen, ...list]);
      _snack("Profile picture updated");
    } catch (e) {
      _snack("Couldn't update: $e");
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> removePhoto(List<String> photos, int index) async {
    setState(() => busy = true);
    try {
      final list = [...photos]..removeAt(index);
      await _save(list);
      _snack("Photo removed");
    } catch (e) {
      _snack("Couldn't remove: $e");
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void showOptions(List<String> photos, int index) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index != 0)
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text("Set as profile picture"),
                onTap: () {
                  Navigator.pop(context);
                  setAsProfile(photos, index);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text("Remove photo", style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text("Delete this photo?"),
                    content: Text(
                      index == 0
                          ? "This is your profile picture. The next photo (if any) becomes your profile picture."
                          : "This photo will be removed from your profile.",
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text("Delete", style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (ok == true) removePhoto(photos, index);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Photos")),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _ref.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text("Couldn't load: ${snap.error}"));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final photos = photosOf(snap.data!.data() ?? {});

            return Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: CircleAvatar(
                        radius: 64,
                        backgroundColor: Colors.grey[300],
                        backgroundImage: photos.isNotEmpty ? NetworkImage(photos.first) : null,
                        child: photos.isEmpty ? const Icon(Icons.person, size: 60, color: Colors.white) : null,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        photos.isEmpty ? "Add a photo to set your profile picture" : "This is your profile picture",
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                    const SizedBox(height: 20),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: [
                        for (int i = 0; i < photos.length; i++)
                          GestureDetector(
                            onTap: busy ? null : () => showOptions(photos, i),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(
                                    photos[i],
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(color: Colors.grey[300], child: const Icon(Icons.broken_image)),
                                  ),
                                  if (i == 0)
                                    Positioned(
                                      left: 4,
                                      bottom: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.pinkAccent, borderRadius: BorderRadius.circular(8)),
                                        child: const Text("Profile", style: TextStyle(color: Colors.white, fontSize: 10)),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        if (photos.length < maxPhotos)
                          GestureDetector(
                            onTap: busy ? null : () => addPhoto(photos),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.pinkAccent),
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo_outlined, color: Colors.pinkAccent),
                                  SizedBox(height: 4),
                                  Text("Add photo", style: TextStyle(color: Colors.pinkAccent, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Tap a photo to set it as your profile picture or remove it.",
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                if (busy)
                  Container(
                    color: Colors.black26,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
