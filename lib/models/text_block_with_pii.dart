import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'pii_entity.dart';
import 'text_element_with_pii.dart';

/// Represents a text block with detected PII information
class TextBlockWithPII {
  /// The original text block from OCR
  final TextBlock originalBlock;

  /// List of detected PII entities in this block
  final List<PIIEntity> detectedPII;

  /// Whether this block is selected by the user
  final bool isSelected;

  /// Whether this block is masked
  final bool isMasked;

  /// The bounding box of the text block
  final Rect boundingBox;

  /// The lines of text in this block
  final List<TextLine> lines;

  /// Map of word elements with their bounding boxes
  final Map<String, Rect> wordBoundingBoxes;

  /// List of text elements with PII information
  final List<TextElementWithPII> elementsWithPII;

  const TextBlockWithPII({
    required this.originalBlock,
    required this.detectedPII,
    this.isSelected = false,
    this.isMasked = false,
    required this.boundingBox,
    required this.lines,
    required this.wordBoundingBoxes,
    required this.elementsWithPII,
  });

  /// Creates a copy of this TextBlockWithPII with updated values
  TextBlockWithPII copyWith({
    TextBlock? originalBlock,
    List<PIIEntity>? detectedPII,
    bool? isSelected,
    bool? isMasked,
    Rect? boundingBox,
    List<TextLine>? lines,
    Map<String, Rect>? wordBoundingBoxes,
    List<TextElementWithPII>? elementsWithPII,
  }) {
    return TextBlockWithPII(
      originalBlock: originalBlock ?? this.originalBlock,
      detectedPII: detectedPII ?? this.detectedPII,
      isSelected: isSelected ?? this.isSelected,
      isMasked: isMasked ?? this.isMasked,
      boundingBox: boundingBox ?? this.boundingBox,
      lines: lines ?? this.lines,
      wordBoundingBoxes: wordBoundingBoxes ?? this.wordBoundingBoxes,
      elementsWithPII: elementsWithPII ?? this.elementsWithPII,
    );
  }

  /// Creates a TextBlockWithPII from a TextBlock
  factory TextBlockWithPII.fromTextBlock(TextBlock block) {
    // Extract word-level bounding boxes and create text elements
    final wordBoxes = <String, Rect>{};
    final elements = <TextElementWithPII>[];

    for (final line in block.lines) {
      for (final element in line.elements) {
        wordBoxes[element.text] = element.boundingBox;
        elements.add(TextElementWithPII(
          element: element,
          detectedPII: [],
          boundingBox: element.boundingBox,
        ));
      }
    }

    return TextBlockWithPII(
      originalBlock: block,
      detectedPII: [],
      boundingBox: block.boundingBox,
      lines: block.lines,
      wordBoundingBoxes: wordBoxes,
      elementsWithPII: elements,
    );
  }

  /// Gets the text content of the block
  String get text => originalBlock.text;

  /// Gets the PII entities that overlap with the given text range
  List<PIIEntity> getPIIInRange(int start, int end) {
    return detectedPII.where((pii) {
      return pii.startIndex >= start && pii.endIndex <= end;
    }).toList();
  }

  /// Gets the bounding box for a specific word in the text
  Rect? getWordBoundingBox(String word) {
    return wordBoundingBoxes[word];
  }

  /// Gets all words that contain PII
  List<String> getWordsWithPII() {
    final words = <String>[];
    for (final pii in detectedPII) {
      final piiText = pii.text;
      // Split PII text into words and find their bounding boxes
      final piiWords = piiText.split(' ');
      for (final word in piiWords) {
        if (wordBoundingBoxes.containsKey(word)) {
          words.add(word);
        }
      }
    }
    return words;
  }

  /// Maps PII entities to text elements
  TextBlockWithPII withMappedPII(List<PIIEntity> piiEntities) {
    final updatedElements = elementsWithPII.map((element) {
      final elementPII = <PIIEntity>[];

      for (final pii in piiEntities) {
        if (_isElementPartOfPII(element, pii)) {
          elementPII.add(pii);
        }
      }

      return element.copyWith(detectedPII: elementPII);
    }).toList();

    return copyWith(
      detectedPII: piiEntities,
      elementsWithPII: updatedElements,
    );
  }

  /// Checks if a text element is part of a PII entity
  bool _isElementPartOfPII(TextElementWithPII element, PIIEntity pii) {
    final elementText = element.text;
    final piiText = pii.text;

    // Case 1: Element text is exactly the PII text
    if (elementText == piiText) return true;

    // Case 2: Element text is part of a multi-word PII
    if (piiText.contains(elementText)) {
      // Get the position of this element in the block's text
      final elementStart = text.indexOf(elementText);
      if (elementStart == -1) return false;

      // Check if the element's position aligns with the PII entity's position
      return elementStart >= pii.startIndex &&
          elementStart + elementText.length <= pii.endIndex;
    }

    return false;
  }

  /// Checks if the given point is within the bounding box
  bool containsPoint(Offset point) {
    return boundingBox.contains(point);
  }

  @override
  String toString() {
    return 'TextBlockWithPII(text: $text, piiCount: ${detectedPII.length}, selected: $isSelected, masked: $isMasked)';
  }
}
