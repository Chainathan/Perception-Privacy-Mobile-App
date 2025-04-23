import 'package:flutter/material.dart';
import 'dart:io';
import 'document_preview_screen.dart';
import 'image_preview_screen.dart';

/// A screen that allows users to select the type of image they have captured or selected.
/// This screen appears after image capture/selection and before the appropriate preview screen.
class ImageTypeSelectionScreen extends StatelessWidget {
  final File imageFile;

  const ImageTypeSelectionScreen({
    Key? key,
    required this.imageFile,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Image Type'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'What type of image is this?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTypeCard(
                  context,
                  'Document',
                  Icons.description,
                  Colors.blue,
                  () => _navigateToDocumentPreview(context),
                ),
                _buildTypeCard(
                  context,
                  'Regular Image',
                  Icons.image,
                  Colors.green,
                  () => _navigateToImagePreview(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        height: 200,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: color,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToDocumentPreview(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => DocumentPreviewScreen(
          initialImage: imageFile,
        ),
      ),
    );
  }

  void _navigateToImagePreview(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ImagePreviewScreen(
          imageFile: imageFile,
        ),
      ),
    );
  }
}
