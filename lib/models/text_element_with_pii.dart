import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'pii_entity.dart';

/// Represents a text element (word) with detected PII information
class TextElementWithPII {
  /// The original text element from OCR
  final TextElement element;

  /// List of detected PII entities that include this text element
  final List<PIIEntity> detectedPII;

  /// Whether this element is selected by the user
  final bool isSelected;

  /// Whether this element is masked
  final bool isMasked;

  /// The bounding box of the text element
  final Rect boundingBox;

  const TextElementWithPII({
    required this.element,
    required this.detectedPII,
    this.isSelected = false,
    this.isMasked = false,
    required this.boundingBox,
  });

  /// Creates a copy of this TextElementWithPII with updated values
  TextElementWithPII copyWith({
    TextElement? element,
    List<PIIEntity>? detectedPII,
    bool? isSelected,
    bool? isMasked,
    Rect? boundingBox,
  }) {
    return TextElementWithPII(
      element: element ?? this.element,
      detectedPII: detectedPII ?? this.detectedPII,
      isSelected: isSelected ?? this.isSelected,
      isMasked: isMasked ?? this.isMasked,
      boundingBox: boundingBox ?? this.boundingBox,
    );
  }

  /// Gets the text content of the element
  String get text => element.text;

  /// Checks if this element contains any PII
  bool get hasPII => detectedPII.isNotEmpty;

  /// Gets the primary PII type if this element contains PII
  PIIEntityType? get primaryPIIType =>
      detectedPII.isNotEmpty ? detectedPII.first.type : null;

  @override
  String toString() {
    return 'TextElementWithPII(text: $text, piiCount: ${detectedPII.length}, selected: $isSelected, masked: $isMasked)';
  }
}
