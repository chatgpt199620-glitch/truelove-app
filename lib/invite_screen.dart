import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class InviteScreen extends StatelessWidget {
  const InviteScreen({super.key});

  // ===== UPDATE THIS with your GitHub repo's "latest release" link =====
  // Using /releases/latest means this link always points to your newest
  // APK automatically — you never have to change it again after new uploads.
  static const String appDownloadLink = "https://github.com/chatgpt199620-glitch/truelove-app/releases/latest";

  void shareInvite() {
    Share.share(
      "Hey! I'm using TrueLove ❤ — a free dating app that connects people across every boundary. "
      "Download it here: $appDownloadLink",
      subject: "Join me on TrueLove",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Invite Friends")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.favorite, color: Colors.red, size: 70),
            const SizedBox(height: 20),
            const Text(
              "Invite your friends to TrueLove",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              "Share the app with people you know — the more people join, the easier it is to find a real connection.",
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: shareInvite,
                icon: const Icon(Icons.share),
                label: const Text("Share Invite Link", style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
