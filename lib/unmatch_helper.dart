import 'package:flutter/material.dart';
import 'user_utils.dart';

/// Asks for confirmation, then ends the connection with [otherUid].
/// Returns true if the unmatch was done.
Future<bool> confirmAndUnmatch(BuildContext context, String otherUid, String otherName) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text("Unmatch $otherName?"),
      content: const Text(
        "You will no longer be connected. The chat will be deleted and neither of you "
        "will be able to send messages. You can send a new request later.",
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text("Unmatch", style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  if (ok != true) return false;

  try {
    await RequestService.unmatch(otherUid);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("You unmatched $otherName")));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Unmatch failed: $e")));
    }
    return false;
  }
}
