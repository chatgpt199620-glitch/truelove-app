import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateNotifier {
  static Future<void> init() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // Ask the user's permission to show notifications (required on Android 13+)
      await messaging.requestPermission();

      // Subscribes this device to the shared "app_updates" mailbox
      await messaging.subscribeToTopic('app_updates');

      // Notification arrives while the app is OPEN
      FirebaseMessaging.onMessage.listen((message) {
        print('Update notification received: ${message.notification?.title}');
      });

      // User taps the notification (app in background)
      FirebaseMessaging.onMessageOpenedApp.listen(_openDownloadLink);

      // App was fully closed and opened BY tapping the notification
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        await _openDownloadLink(initialMessage);
      }
    } catch (e) {
      print('UpdateNotifier error: $e');
    }
  }

  static Future<void> _openDownloadLink(RemoteMessage message) async {
    final link = message.data['download_url'] ?? message.data['downloadUrl'];
    if (link != null) {
      await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    }
  }
}