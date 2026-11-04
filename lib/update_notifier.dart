import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateNotifier {
  static Future<void> init() async {
    final messaging = FirebaseMessaging.instance;

    // Ask the user's permission to show notifications (required on Android 13+)
    await messaging.requestPermission();

    // This subscribes EVERY device that has this app to a shared "mailbox"
    // named "app_updates" — this is how one message reaches everyone at once.
    await messaging.subscribeToTopic('app_updates');

    // What happens when a notification arrives while the app is OPEN
    FirebaseMessaging.onMessage.listen((message) {
      // For now, we just print it — later we can show an in-app popup too.
      print('Update notification received: ${message.notification?.title}');
    });

    // What happens when the user TAPS a notification (app was closed/background)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _openDownloadLink(message);
    });

    // Handles the case where the app was completely closed and opened BY tapping the notification
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _openDownloadLink(initialMessage);
    }
  }

  static void _openDownloadLink(RemoteMessage message) async {
    final link = message.data['downloadUrl'];
    if (link != null) {
      final uri = Uri.parse(link);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
}