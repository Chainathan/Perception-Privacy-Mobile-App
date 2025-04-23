import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../models/text_block_with_pii.dart';

/// Service for masking text blocks containing PII in document images
class TextPIIMaskingService {
  /// Masks selected text blocks containing PII in the document image with a solid color
  Future<File> maskDocument(
    File originalImage,
    List<TextBlockWithPII> maskedBlocks,
    Color maskColor,
  ) async {
    try {
      // Load the original image
      final imageBytes = await originalImage.readAsBytes();
      final image = img.decodeImage(imageBytes);

      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // Create a new image with the same dimensions
      final maskedImage = img.Image(width: image.width, height: image.height);

      // Copy the original image
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          maskedImage.setPixel(x, y, image.getPixel(x, y));
        }
      }

      // Apply masks to selected blocks
      for (final block in maskedBlocks) {
        if (!block.isMasked) continue;

        // Get all elements that contain PII
        final piiElements =
            block.elementsWithPII.where((e) => e.hasPII).toList();

        // Mask each PII element individually
        for (final element in piiElements) {
          final box = element.boundingBox;

          // Convert the element's bounding box to image coordinates
          final startX = box.left.round();
          final startY = box.top.round();
          final endX = box.right.round();
          final endY = box.bottom.round();

          // Add some padding around the element for better masking
          final padding = 2;
          final paddedStartX = max(0, startX - padding);
          final paddedStartY = max(0, startY - padding);
          final paddedEndX = min(image.width, endX + padding);
          final paddedEndY = min(image.height, endY + padding);

          // Fill the element area with the mask color
          for (var y = paddedStartY; y < paddedEndY; y++) {
            for (var x = paddedStartX; x < paddedEndX; x++) {
              maskedImage.setPixel(
                x,
                y,
                img.ColorRgba8(
                  maskColor.red,
                  maskColor.green,
                  maskColor.blue,
                  maskColor.alpha,
                ),
              );
            }
          }
        }
      }

      // Save the masked image
      final maskedImageBytes = img.encodePng(maskedImage);
      final maskedFile = File('${originalImage.path}_masked.png');
      await maskedFile.writeAsBytes(maskedImageBytes);

      return maskedFile;
    } catch (e) {
      debugPrint('Error masking document: $e');
      rethrow;
    }
  }

  /// Helper function to get the minimum of two integers
  int min(int a, int b) => a < b ? a : b;

  /// Helper function to get the maximum of two integers
  int max(int a, int b) => a > b ? a : b;

  /// Saves the masked document to a file
  Future<File> saveMaskedDocument(File maskedImage) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final savedFile = File('masked_document_$timestamp.png');
      await maskedImage.copy(savedFile.path);
      return savedFile;
    } catch (e) {
      debugPrint('Error saving masked document: $e');
      rethrow;
    }
  }
}
