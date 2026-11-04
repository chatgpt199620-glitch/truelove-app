import 'dart:io';
import 'package:flutter/material.dart';

class FullPhotoView extends StatelessWidget {
  final String? networkUrl;
  final File? localFile;
  const FullPhotoView({super.key, this.networkUrl, this.localFile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: localFile != null
              ? Image.file(localFile!, fit: BoxFit.contain)
              : networkUrl != null
                  ? Image.network(networkUrl!, fit: BoxFit.contain)
                  : const Icon(Icons.broken_image, color: Colors.white, size: 60),
        ),
      ),
    );
  }
}