import 'package:flutter/material.dart';
import 'main.dart';

class GuidelinesScreen extends StatefulWidget {
  const GuidelinesScreen({super.key});
  @override
  State<GuidelinesScreen> createState() => _GuidelinesScreenState();
}

class _GuidelinesScreenState extends State<GuidelinesScreen> {
  bool agreed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Community Guidelines")),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text("Before you join TrueLove", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  SizedBox(height: 16),
                  Text("• You must be 18 years or older to use this app.\n\n"
                      "• Be respectful. Harassment, hate speech, or discrimination based on caste, religion, gender, or background is not tolerated.\n\n"
                      "• Never send money, gift cards, OTPs, or banking details to anyone you meet on this app. Any such request is a scam — report it immediately.\n\n"
                      "• Creating fake profiles, impersonating someone else, or posting explicit content will result in a permanent ban.\n\n"
                      "• Always meet new connections in public places, and let a friend or family member know your plans.\n\n"
                      "• Report and Block are available in every chat — use them if something feels wrong.",
                      style: TextStyle(fontSize: 14, height: 1.6)),
                  SizedBox(height: 20),
                  Text("Limitation of liability", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text("TrueLove is a platform that helps people connect. We are not responsible for the conduct of "
                      "users once they interact on or off the app, including in-person meetings. By using this app, "
                      "you agree that the app owner is not liable for any loss, harm, dispute, or damage arising from "
                      "your interactions with other users, to the fullest extent permitted by law.",
                      style: TextStyle(fontSize: 14, height: 1.6)),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: const Offset(0, -2))],
            ),
            child: Column(
              children: [
                CheckboxListTile(
                  value: agreed,
                  onChanged: (v) => setState(() => agreed = v ?? false),
                  title: const Text(
                    "I have read and agree to the Community Guidelines, and I understand the app owner is not responsible for issues arising from my use of this app.",
                    style: TextStyle(fontSize: 13),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                    onPressed: agreed
                        ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthScreen(register: true)))
                        : null,
                    child: const Text("Continue"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}