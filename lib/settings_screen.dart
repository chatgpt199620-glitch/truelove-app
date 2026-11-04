import 'edit_photo_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_utils.dart';
import 'account_deletion.dart';
import 'full_photo_view.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'main.dart';
import 'presence_service.dart';
import 'profile_options.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String imageKitPublicKey = "public_HUkjSbvXqQ7SfBAwyBXJPsak++A=";
  static const int maxPhotos = 6;

  final nameCtrl = TextEditingController();
  final nicknameCtrl = TextEditingController();
  final bioCtrl = TextEditingController();
  final interestsCtrl = TextEditingController();

  // Details from registration - editable here
  final occupationCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final stateCtrl = TextEditingController();
  final countryCtrl = TextEditingController();
  String? relationshipStatus, lookingFor, religion, motherTongue, education, employedIn, diet;
  int? heightCm;

  List<String> savedPhotoUrls = [];
  List<File?> newLocalPhotos = List.filled(6, null);
  bool loading = true;
  bool saving = false;
  bool deleting = false;
  bool changingMainPhoto = false;
  String message = "";

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future<void> loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data();
    if (data != null) {
      nameCtrl.text = data['name'] ?? '';
      nicknameCtrl.text = data['nickname'] ?? '';
      bioCtrl.text = data['bio'] ?? '';
      interestsCtrl.text = (data['interests'] as List?)?.join(', ') ?? '';
      String? pick(String key, List<String> options) {
        final v = data[key]?.toString();
        return (v != null && options.contains(v)) ? v : null;
      }
      relationshipStatus = pick('relationshipStatus', kRelationshipOptions);
      lookingFor = pick('lookingFor', kLookingForOptions);
      religion = pick('religion', kReligionOptions);
      motherTongue = pick('motherTongue', kMotherTongueOptions);
      education = pick('education', kEducationOptions);
      employedIn = pick('employedIn', kEmployedInOptions);
      diet = pick('diet', kDietOptions);
      final h = (data['heightCm'] as num?)?.toInt();
      heightCm = (h != null && kHeightsCm.contains(h)) ? h : null;
      occupationCtrl.text = (data['occupation'] ?? '').toString();
      cityCtrl.text = (data['city'] ?? data['location'] ?? '').toString();
      stateCtrl.text = (data['state'] ?? '').toString();
      countryCtrl.text = (data['country'] ?? '').toString();
      savedPhotoUrls = (data['photos'] as List?)?.cast<String>() ??
          (data['photoUrl'] != null ? [data['photoUrl'] as String] : []);
    }
    setState(() => loading = false);
  }

  Future<void> pickImageAt(int slotIndex) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null) {
      setState(() => newLocalPhotos[slotIndex] = File(picked.path));
    }
  }

  void removeSavedPhoto(int index) {
    setState(() => savedPhotoUrls.removeAt(index));
  }

  void removeNewPhoto(int index) {
    setState(() => newLocalPhotos[index] = null);
  }

Future<String?> uploadToImageKit(File imageFile, String fileName) async {
  try {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return await uploadProfilePhoto(imageFile, uid, fileName);
  } catch (e) {
    return null;
  }
}
  Future<String?> uploadToImageKitold(File imageFile, String fileName) async {
    if (imageKitPublicKey == "YOUR_PUBLIC_KEY_HERE" || imageKitPublicKey.trim().isEmpty) {
      return null;
    }
    try {
      final url = Uri.parse("https://upload.imagekit.io/api/v1/files/upload");
      final request = http.MultipartRequest('POST', url)
        ..fields['publicKey'] = imageKitPublicKey
        ..fields['fileName'] = fileName
        ..fields['useUniqueFileName'] = 'true'
        ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));
      final response = await request.send();
      final body = await response.stream.bytesToString();
      if (response.statusCode == 200) {
        return jsonDecode(body)['url'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> changeMainPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return;

    setState(() => changingMainPhoto = true);
    try {
      final file = File(picked.path);
      final url = await uploadToImageKit(file, 'main_${DateTime.now().millisecondsSinceEpoch}.jpg');

      if (url == null) {
        setState(() {
          changingMainPhoto = false;
          message = "⚠️ Profile photo upload failed. Check your connection or Cloudinary setup in user_utils.dart.";
        });
        return;
      }

      final uid = FirebaseAuth.instance.currentUser!.uid;
      List<String> updatedPhotos = List.from(savedPhotoUrls);
      if (updatedPhotos.isNotEmpty) {
        updatedPhotos[0] = url;
      } else {
        updatedPhotos.insert(0, url);
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'photos': updatedPhotos,
        'photoUrl': updatedPhotos.first,
      });

      setState(() {
        savedPhotoUrls = updatedPhotos;
        changingMainPhoto = false;
        message = "✅ Profile photo updated!";
      });
    } catch (e) {
      setState(() {
        changingMainPhoto = false;
        message = "Error: $e";
      });
    }
  }

  Future<void> removeMainPhoto() async {
    if (savedPhotoUrls.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Remove profile photo?"),
        content: const Text("Your profile will show a default icon until you add a new photo."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Remove", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => changingMainPhoto = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      List<String> updatedPhotos = List.from(savedPhotoUrls)..removeAt(0);

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'photos': updatedPhotos,
        'photoUrl': updatedPhotos.isNotEmpty ? updatedPhotos.first : null,
      });

      setState(() {
        savedPhotoUrls = updatedPhotos;
        changingMainPhoto = false;
        message = "✅ Profile photo removed.";
      });
    } catch (e) {
      setState(() {
        changingMainPhoto = false;
        message = "Error: $e";
      });
    }
  }

  void showMainPhotoOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (savedPhotoUrls.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text("View photo"),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => FullPhotoView(networkUrl: savedPhotoUrls.first),
                  ));
                },
              ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text("Change profile photo"),
              onTap: () {
                Navigator.pop(context);
                changeMainPhoto();
              },
            ),
            if (savedPhotoUrls.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text("Remove profile photo", style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  removeMainPhoto();
                },
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text("Cancel"),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> saveChanges() async {
    setState(() { saving = true; message = ""; });

    if (imageKitPublicKey == "YOUR_PUBLIC_KEY_HERE" || imageKitPublicKey.trim().isEmpty) {
      bool hasNewPhoto = newLocalPhotos.any((f) => f != null);
      if (hasNewPhoto) {
        setState(() {
          saving = false;
          message = "⚠️ Can't upload photos yet — ImageKit key not set in code.";
        });
      }
    }

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      List<String> finalPhotoUrls = List.from(savedPhotoUrls);
      List<int> failedSlots = [];

      for (int i = 0; i < newLocalPhotos.length; i++) {
        final file = newLocalPhotos[i];
        if (file != null) {
          final uploadedUrl = await uploadToImageKit(file, '${uid}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg');
          if (uploadedUrl != null) {
            finalPhotoUrls.add(uploadedUrl);
          } else {
            failedSlots.add(i);
          }
        }
      }

      if (finalPhotoUrls.length > maxPhotos) {
        finalPhotoUrls = finalPhotoUrls.sublist(0, maxPhotos);
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'name': nameCtrl.text.trim(),
        'nickname': nicknameCtrl.text.trim(),
        'bio': bioCtrl.text.trim(),
        'interests': interestsCtrl.text.trim().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        'photos': finalPhotoUrls,
        if (relationshipStatus != null) 'relationshipStatus': relationshipStatus,
        if (lookingFor != null) 'lookingFor': lookingFor,
        if (religion != null) 'religion': religion,
        if (motherTongue != null) 'motherTongue': motherTongue,
        if (education != null) 'education': education,
        if (employedIn != null) 'employedIn': employedIn,
        if (diet != null) 'diet': diet,
        if (heightCm != null) 'heightCm': heightCm,
        if (heightCm != null) 'height': heightLabel(heightCm!),
        'occupation': occupationCtrl.text.trim(),
        'city': cityCtrl.text.trim(),
        'location': cityCtrl.text.trim(),
        'state': stateCtrl.text.trim(),
        'country': countryCtrl.text.trim(),
        if (finalPhotoUrls.isNotEmpty) 'photoUrl': finalPhotoUrls.first,
      });

      setState(() {
        savedPhotoUrls = finalPhotoUrls;
        for (int i = 0; i < newLocalPhotos.length; i++) {
          if (!failedSlots.contains(i)) newLocalPhotos[i] = null;
        }
        if (failedSlots.isEmpty) {
          message = "✅ Profile updated successfully!";
        } else {
          message = "✅ Text saved. ⚠️ ${failedSlots.length} photo(s) failed — tap Save again to retry.";
        }
      });
    } catch (e) {
      setState(() => message = "Error: $e");
    } finally {
      setState(() => saving = false);
    }
  }

  Future<void> logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Log out?"),
        content: const Text("You'll need to log in again to use the app."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Log out")),
        ],
      ),
    );
    if (confirm != true) return;

    await PresenceService().setOnline(false);
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const StartupGate()), (route) => false);
    }
  }

  Future<void> changePassword() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Password reset is only available for email accounts.")),
      );
      return;
    }
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Password reset link sent to $email")),
      );
    }
  }

  Future<void> viewBlockedUsers() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseFirestore.instance.collection('users').doc(uid).collection('blocked').get();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => SizedBox(
        height: 400,
        child: snap.docs.isEmpty
            ? const Center(child: Text("No blocked users"))
            : ListView.builder(
                itemCount: snap.docs.length,
                itemBuilder: (context, i) {
                  final blockedUid = snap.docs[i].id;
                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('users').doc(blockedUid).get(),
                    builder: (context, userSnap) {
                      final userData = userSnap.data?.data() as Map<String, dynamic>?;
                      return ListTile(
                        title: Text(userData?['name'] ?? 'Unknown user'),
                        trailing: TextButton(
                          onPressed: () async {
                            await FirebaseFirestore.instance.collection('users').doc(uid).collection('blocked').doc(blockedUid).delete();
                            if (mounted) Navigator.pop(context);
                          },
                          child: const Text("Unblock"),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }

  Future<void> deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete account?"),
        content: const Text("This permanently deletes your profile, photos, matches, and requests. This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;

    setState(() => deleting = true);

    try {
      await PresenceService().setOnline(false);

      final matchesSnap = await FirebaseFirestore.instance
          .collection('matches').where('users', arrayContains: uid).get();
      for (final doc in matchesSnap.docs) {
        await doc.reference.delete();
      }

      final sentRequests = await FirebaseFirestore.instance
          .collection('requests').where('from', isEqualTo: uid).get();
      for (final doc in sentRequests.docs) {
        await doc.reference.delete();
      }
      final receivedRequests = await FirebaseFirestore.instance
          .collection('requests').where('to', isEqualTo: uid).get();
      for (final doc in receivedRequests.docs) {
        await doc.reference.delete();
      }

      final sentLikes = await FirebaseFirestore.instance
          .collection('likes').where('from', isEqualTo: uid).get();
      for (final doc in sentLikes.docs) {
        await doc.reference.delete();
      }
      final receivedLikes = await FirebaseFirestore.instance
          .collection('likes').where('to', isEqualTo: uid).get();
      for (final doc in receivedLikes.docs) {
        await doc.reference.delete();
      }

      final notifSnap = await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('notifications').get();
      for (final doc in notifSnap.docs) {
        await doc.reference.delete();
      }

      final blockedSnap = await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('blocked').get();
      for (final doc in blockedSnap.docs) {
        await doc.reference.delete();
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      await user.delete();

      if (mounted) {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const StartupGate()), (route) => false);
      }
    } catch (e) {
      setState(() => deleting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't fully delete account: $e. You may need to log in again first, then retry.")),
        );
      }
    }
  }

  Widget photoSlot(int index) {
    final hasSaved = index < savedPhotoUrls.length;
    final hasNew = newLocalPhotos[index] != null;

    return GestureDetector(
      onTap: () {
        if (hasNew) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => FullPhotoView(localFile: newLocalPhotos[index]),
          ));
        } else if (hasSaved) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => FullPhotoView(networkUrl: savedPhotoUrls[index]),
          ));
        } else {
          pickImageAt(index);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(10),
          border: hasNew ? Border.all(color: Colors.orange, width: 2) : null,
          image: hasNew
              ? DecorationImage(image: FileImage(newLocalPhotos[index]!), fit: BoxFit.cover)
              : hasSaved
                  ? DecorationImage(image: NetworkImage(savedPhotoUrls[index]), fit: BoxFit.cover)
                  : null,
        ),
        child: Stack(
          children: [
            if (!hasSaved && !hasNew)
              const Center(child: Icon(Icons.add_a_photo, color: Colors.grey)),
            if (hasSaved || hasNew)
              Positioned(
                bottom: 2, left: 2,
                child: GestureDetector(
                  onTap: () => pickImageAt(index),
                  child: const CircleAvatar(radius: 10, backgroundColor: Colors.black54, child: Icon(Icons.edit, size: 12, color: Colors.white)),
                ),
              ),
            if (hasNew)
              Positioned(
                top: 2, right: 2,
                child: GestureDetector(
                  onTap: () => removeNewPhoto(index),
                  child: const CircleAvatar(radius: 10, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 13, color: Colors.white)),
                ),
              ),
            if (hasSaved && !hasNew)
              Positioned(
                top: 2, right: 2,
                child: GestureDetector(
                  onTap: () => removeSavedPhoto(index),
                  child: const CircleAvatar(radius: 10, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 13, color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget detailDropdown(String label, String? value, List<String> items, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget detailText(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(controller: c, decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder())),
    );
  }

  Widget sectionCard({required String title, required IconData icon, required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Icon(icon, size: 18, color: Colors.red),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget simpleTile({required IconData icon, required String title, required VoidCallback onTap, Color? color}) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color ?? Colors.black54, size: 20),
      title: Text(title, style: TextStyle(color: color, fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text("Settings")),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 30),
            children: [
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: showMainPhotoOptions,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 45,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: savedPhotoUrls.isNotEmpty ? NetworkImage(savedPhotoUrls.first) : null,
                            child: savedPhotoUrls.isEmpty ? const Icon(Icons.person, size: 40, color: Colors.grey) : null,
                          ),
                          if (changingMainPhoto)
                            Positioned.fill(
                              child: CircleAvatar(
                                radius: 45,
                                backgroundColor: Colors.black38,
                                child: const CircularProgressIndicator(color: Colors.white),
                              ),
                            ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                              child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text("Tap photo to view, change or remove", style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 10),
                    Text(nameCtrl.text.isEmpty ? "Your Name" : nameCtrl.text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    if (nicknameCtrl.text.isNotEmpty) Text("@${nicknameCtrl.text}", style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              sectionCard(
                title: "Edit Profile",
                icon: Icons.edit_outlined,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text("More Photos (tap to view, pencil icon to change)", style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 8),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                          itemCount: maxPhotos,
                          itemBuilder: (context, i) => photoSlot(i),
                        ),
                        const SizedBox(height: 14),
                        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Full name", isDense: true, border: OutlineInputBorder())),
                        const SizedBox(height: 10),
                        TextField(controller: nicknameCtrl, decoration: const InputDecoration(labelText: "Nickname", isDense: true, border: OutlineInputBorder())),
                        const SizedBox(height: 10),
                        TextField(controller: bioCtrl, maxLines: 3, decoration: const InputDecoration(labelText: "Bio", isDense: true, border: OutlineInputBorder())),
                        const SizedBox(height: 10),
                        TextField(controller: interestsCtrl, decoration: const InputDecoration(labelText: "Interests (comma separated)", isDense: true, border: OutlineInputBorder())),
                        const SizedBox(height: 18),
                        const Text("About me", style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text("Date of birth and gender can't be changed.", style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 10),
                        detailDropdown("Relationship status", relationshipStatus, kRelationshipOptions, (v) => setState(() => relationshipStatus = v)),
                        detailDropdown("I'm looking for", lookingFor, kLookingForOptions, (v) => setState(() => lookingFor = v)),
                        DropdownButtonFormField<int>(
                          value: heightCm,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: "Height", isDense: true, border: OutlineInputBorder()),
                          items: kHeightsCm.map((cm) => DropdownMenuItem(value: cm, child: Text(heightLabel(cm)))).toList(),
                          onChanged: (v) => setState(() => heightCm = v),
                        ),
                        const SizedBox(height: 10),
                        detailDropdown("Diet", diet, kDietOptions, (v) => setState(() => diet = v)),
                        detailDropdown("Religion", religion, kReligionOptions, (v) => setState(() => religion = v)),
                        detailDropdown("Mother tongue", motherTongue, kMotherTongueOptions, (v) => setState(() => motherTongue = v)),
                        detailDropdown("Highest education", education, kEducationOptions, (v) => setState(() => education = v)),
                        detailDropdown("Working in", employedIn, kEmployedInOptions, (v) => setState(() => employedIn = v)),
                        detailText(occupationCtrl, "Occupation / Profession"),
                        detailText(cityCtrl, "City"),
                        detailText(stateCtrl, "State"),
                        detailText(countryCtrl, "Country"),
                        const SizedBox(height: 14),
                        if (saving) const Center(child: CircularProgressIndicator()) else
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                              onPressed: saveChanges,
                              child: const Text("Save Changes"),
                            ),
                          ),
                        const SizedBox(height: 6),
                        if (message.isNotEmpty)
                          Text(message, style: TextStyle(color: message.startsWith("✅") ? Colors.green : Colors.orange[800], fontSize: 12)),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ],
              ),
              sectionCard(
                title: "Account",
                icon: Icons.manage_accounts_outlined,
                children: [
                  simpleTile(icon: Icons.lock_outline, title: "Change password", onTap: changePassword),
                  simpleTile(icon: Icons.block, title: "Blocked users", onTap: viewBlockedUsers),
                ],
              ),
              sectionCard(
                title: "Support",
                icon: Icons.support_agent_outlined,
                children: [
                  simpleTile(
                    icon: Icons.help_outline,
                    title: "Help & Support",
                    onTap: () => showDialog(context: context, builder: (_) => AlertDialog(
                      title: const Text("Help & Support"),
                      content: const Text("For help, contact us at support@truelove.app"),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
                    )),
                  ),
                  simpleTile(
                    icon: Icons.shield_outlined,
                    title: "Safety tips",
                    onTap: () => showDialog(context: context, builder: (_) => AlertDialog(
                      title: const Text("Safety tips"),
                      content: const Text("• Meet in public places\n• Never send money or OTPs\n• Tell a friend your plans\n• Trust your instincts"),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
                    )),
                  ),
                  simpleTile(
                    icon: Icons.privacy_tip_outlined,
                    title: "Privacy Policy",
                    onTap: () => showDialog(context: context, builder: (_) => AlertDialog(
                      title: const Text("Privacy Policy"),
                      content: const SingleChildScrollView(
                        child: Text("We collect your email/phone, profile info, and messages to operate the app. "
                            "We do not sell your data. You can request deletion of your account and data at any time. "
                            "This app is for users 18 years and older only."),
                      ),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
                    )),
                  ),
                  simpleTile(
                    icon: Icons.description_outlined,
                    title: "Terms & Community Guidelines",
                    onTap: () => showDialog(context: context, builder: (_) => AlertDialog(
                      title: const Text("Terms & Guidelines"),
                      content: const SingleChildScrollView(
                        child: Text("By using TrueLove, you agree to be respectful and never request money from other "
                            "users. Abusive or vulgar behavior results in immediate, permanent account suspension."),
                      ),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
                    )),
                  ),
                  simpleTile(
                    icon: Icons.info_outline,
                    title: "About TrueLove",
                    onTap: () => showDialog(context: context, builder: (_) => AlertDialog(
                      title: const Text("About TrueLove"),
                      content: const Text("TrueLove v1.0\nConnecting people across every boundary."),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
                    )),
                  ),
                ],
              ),
              sectionCard(
                title: "Danger Zone",
                icon: Icons.warning_amber_outlined,
                children: [
                  simpleTile(icon: Icons.logout, title: "Log out", color: Colors.red, onTap: logout),
                  simpleTile(icon: Icons.delete_outline, title: "Delete account", color: Colors.red, onTap: () => deleteAccountFlow(context)),
                ],
              ),
            ],
          ),
          if (deleting)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text("Deleting your account and all related data..."),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}