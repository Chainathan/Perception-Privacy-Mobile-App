import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/text_block_with_pii.dart';
import '../models/pii_entity.dart';
import 'chatgpt_service.dart';

/// Enhanced OCR service that integrates text recognition with PII detection
class EnhancedOcrService {
  final TextRecognizer _textRecognizer;
  final ChatGPTService _chatGptService;

  /// Maximum text length to send in a single API call
  static const int _maxTextLengthPerCall = 1000;

  /// Creates a new instance of EnhancedOcrService
  EnhancedOcrService({
    required TextRecognizer textRecognizer,
    required ChatGPTService chatGptService,
  })  : _textRecognizer = textRecognizer,
        _chatGptService = chatGptService;

  /// Process a document image and detect PII in the extracted text
  Future<List<TextBlockWithPII>> processDocument(File imageFile) async {
    try {
      // Extract text blocks using OCR
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      debugPrint(
          'OCR completed. Found ${recognizedText.blocks.length} text blocks');

      // Check if any text was recognized
      if (recognizedText.blocks.isEmpty) {
        debugPrint('No text recognized in the image');
        return [];
      }

      // Debug: print some recognized text
      if (recognizedText.blocks.isNotEmpty) {
        debugPrint(
            'Sample recognized text: ${recognizedText.blocks.first.text}');
      }

      // Convert text blocks to TextBlockWithPII
      final textBlocks = recognizedText.blocks
          .map((block) => TextBlockWithPII.fromTextBlock(block))
          .toList();

      // Process text blocks in batches to minimize API calls
      await _processTextBlocksInBatches(textBlocks);

      return textBlocks;
    } catch (e) {
      debugPrint('Error processing document: $e');
      return []; // Return empty list instead of rethrowing
    }
  }

  /// Process text blocks in batches to minimize API calls
  Future<void> _processTextBlocksInBatches(
      List<TextBlockWithPII> textBlocks) async {
    if (textBlocks.isEmpty) return;

    debugPrint('Processing ${textBlocks.length} text blocks in batches');

    // Group text blocks into batches based on text length
    final batches = <List<TextBlockWithPII>>[];
    var currentBatch = <TextBlockWithPII>[];
    var currentBatchLength = 0;

    for (final block in textBlocks) {
      final blockLength = block.text.length;

      // If adding this block would exceed the limit, start a new batch
      if (currentBatchLength + blockLength > _maxTextLengthPerCall &&
          currentBatch.isNotEmpty) {
        batches.add(currentBatch);
        currentBatch = [];
        currentBatchLength = 0;
      }

      currentBatch.add(block);
      currentBatchLength += blockLength;
    }

    // Add the last batch if it's not empty
    if (currentBatch.isNotEmpty) {
      batches.add(currentBatch);
    }

    debugPrint('Created ${batches.length} batches for processing');

    // Process each batch
    for (int i = 0; i < batches.length; i++) {
      debugPrint('Processing batch ${i + 1} of ${batches.length}');
      await _processBatch(batches[i], textBlocks);
    }
  }

  /// Process a batch of text blocks
  Future<void> _processBatch(
      List<TextBlockWithPII> batch, List<TextBlockWithPII> textBlocks) async {
    try {
      // Combine text from all blocks in the batch with clear separators
      final batchTexts = <String>[];
      final originalIndices = <int>[]; // Track original indices in textBlocks

      for (int i = 0; i < batch.length; i++) {
        final block = batch[i];
        batchTexts.add(block.text);
        originalIndices.add(textBlocks.indexOf(block)); // Store original index
      }

      final combinedText = batchTexts.join('\n');
      debugPrint('Combined batch text length: ${combinedText.length}');

      // Detect PII in combined text
      final piiEntities = await _chatGptService.detectPII(combinedText);
      debugPrint('Found ${piiEntities.length} PII entities in batch');

      // Map PII entities back to individual blocks using text matching
      for (int i = 0; i < batch.length; i++) {
        final block = batch[i];
        final blockText = block.text;
        final blockPIIEntities = <PIIEntity>[];

        // Find PII entities that match this block's text
        for (final pii in piiEntities) {
          // Find the position of the PII text in the block
          final piiText = pii.text;
          final startIndex = blockText.indexOf(piiText);

          if (startIndex != -1) {
            // Found a match, create a new PII entity with correct indices
            blockPIIEntities.add(PIIEntity(
              text: piiText,
              type: pii.type,
              startIndex: startIndex,
              endIndex: startIndex + piiText.length,
              confidence: pii.confidence,
            ));

            debugPrint(
                'Found PII match in block ${i + 1}: ${pii.type} - "$piiText" at indices $startIndex-${startIndex + piiText.length}');
          }
        }

        // Update both the batch and the original textBlocks list with mapped PII
        if (blockPIIEntities.isNotEmpty) {
          debugPrint(
              'Block ${i + 1} has ${blockPIIEntities.length} PII entities: ${blockPIIEntities.map((e) => '${e.type}: ${e.text}').join(', ')}');
          final updatedBlock = block.withMappedPII(blockPIIEntities);
          batch[i] = updatedBlock;
          textBlocks[originalIndices[i]] = updatedBlock; // Update original list
        }
      }
    } catch (e) {
      debugPrint('Error processing batch: $e');
      // Continue processing other batches
    }
  }

  /// Helper function to get the minimum of two integers
  int min(int a, int b) => a < b ? a : b;

  /// Helper function to get the maximum of two integers
  int max(int a, int b) => a > b ? a : b;

  /// Dispose of resources
  void dispose() {
    _textRecognizer.close();
  }
}
