import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';

// Lets us show a popup from anywhere in the app
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class UpdateNotifier {
  static bool _dialogOpen = false;

  static Future<void> init() async {
    try {
      final messaging = FirebaseMessaging.instance;

      await messaging.requestPermission();
      await messaging.subscribeToTopic('app_updates');

      // Notification arrives while the app is OPEN: show the popup directly
      FirebaseMessaging.onMessage.listen(_showUpdateDialog);

      // User taps the notification while the app is in the background
      FirebaseMessaging.onMessageOpenedApp.listen(_showUpdateDialog);

      // App was closed and opened BY tapping the notification
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        // Wait a moment so the app screen is ready
        Future.delayed(const Duration(seconds: 2), () => _showUpdateDialog(initial));
      }
    } catch (e) {
      debugPrint('UpdateNotifier error: $e');
    }
  }

  static void _showUpdateDialog(RemoteMessage message) {
    final link = message.data['download_url'] ?? message.data['downloadUrl'];
    final context = navigatorKey.currentContext;
    if (link == null || context == null || _dialogOpen) return;

    _dialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(url: link),
    ).then((_) => _dialogOpen = false);
  }
}

class _UpdateDialog extends StatefulWidget {
  final String url;
  const _UpdateDialog({required this.url});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  int _progress = 0;
  String _status = 'A new version of TrueLove is ready.';

  Future<void> _openInBrowser() async {
    await launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication);
  }

  void _startUpdate() {
    setState(() {
      _downloading = true;
      _progress = 0;
      _status = 'Downloading...';
    });

    try {
      OtaUpdate()
          .execute(widget.url, destinationFilename: 'app-release.apk')
          .listen(
        (OtaEvent event) {
          if (!mounted) return;
          switch (event.status) {
            case OtaStatus.DOWNLOADING:
              setState(() {
                _progress = int.tryParse(event.value ?? '0') ?? 0;
                _status = 'Downloading... $_progress%';
              });
              break;
            case OtaStatus.INSTALLING:
              setState(() => _status = 'Opening installer. Tap Install on the next screen.');
              break;
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
              setState(() {
                _downloading = false;
                _status = 'Please allow "Install unknown apps" for TrueLove, then tap Update now again.';
              });
              break;
            case OtaStatus.INSTALLATION_DONE:
              break;
            default:
              // Any other problem: fall back to the browser download
              setState(() {
                _downloading = false;
                _status = 'Could not download inside the app. Opening browser instead...';
              });
              _openInBrowser();
          }
        },
        onError: (_) {
          if (!mounted) return;
          setState(() {
            _downloading = false;
            _status = 'Download failed. Opening browser instead...';
          });
          _openInBrowser();
        },
      );
    } catch (e) {
      setState(() {
        _downloading = false;
        _status = 'Download failed. Opening browser instead...';
      });
      _openInBrowser();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Update available'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_status),
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress > 0 ? _progress / 100 : null),
          ],
        ],
      ),
      actions: [
        if (!_downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
        if (!_downloading)
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: _startUpdate,
            child: const Text('Update now'),
          ),
      ],
    );
  }
}