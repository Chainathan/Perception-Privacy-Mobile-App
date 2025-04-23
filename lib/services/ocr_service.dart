import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/foundation.dart';

/// A service class that handles OCR operations using Google ML Kit.
/// This class manages text extraction from images.
class OcrService {
  final TextRecognizer _textRecognizer = TextRecognizer();

  /// Extracts text from an image file
  /// Returns a list of text blocks with their bounding boxes
  Future<List<TextBlock>> extractText(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      return recognizedText.blocks;
    } catch (e) {
      debugPrint('Error extracting text: $e');
      throw Exception('Failed to extract text: $e');
    }
  }

  /// Disposes of the text recognizer when no longer needed
  void dispose() {
    _textRecognizer.close();
  }
}
