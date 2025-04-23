import 'package:flutter/material.dart';

/// Represents a detected Personally Identifiable Information (PII) entity
class PIIEntity {
  /// The actual text content of the PII
  final String text;

  /// The type of PII (e.g., name, email, phone)
  final PIIEntityType type;

  /// Starting index of the entity in the original text
  final int startIndex;

  /// Ending index of the entity in the original text
  final int endIndex;

  /// Confidence score of the detection (0.0 to 1.0)
  final double confidence;

  const PIIEntity({
    required this.text,
    required this.type,
    required this.startIndex,
    required this.endIndex,
    required this.confidence,
  });

  /// Creates a PIIEntity from a JSON map
  factory PIIEntity.fromJson(Map<String, dynamic> json) {
    return PIIEntity(
      text: json['text'] as String,
      type: PIIEntityType.values.firstWhere(
        (e) => e.toString() == 'PIIEntityType.${json['type']}',
        orElse: () => PIIEntityType.other,
      ),
      startIndex: json['start_index'] as int,
      endIndex: json['end_index'] as int,
      confidence: (json['confidence'] as num).toDouble(),
    );
  }

  /// Converts the PIIEntity to a JSON map
  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'type': type.toString().split('.').last,
      'start_index': startIndex,
      'end_index': endIndex,
      'confidence': confidence,
    };
  }

  @override
  String toString() {
    return 'PIIEntity(text: $text, type: $type, confidence: $confidence)';
  }
}

/// Enum representing different types of PII entities
enum PIIEntityType {
  /// Person's name
  name,

  /// Email address
  email,

  /// Phone number
  phone,

  /// Physical address
  address,

  /// Social Security Number
  ssn,

  /// Credit card number
  creditCard,

  /// Date (birth date, etc.)
  date,

  /// Other types of PII
  other;

  /// Returns a user-friendly display name for the PII type
  String get displayName {
    switch (this) {
      case PIIEntityType.name:
        return 'Name';
      case PIIEntityType.email:
        return 'Email';
      case PIIEntityType.phone:
        return 'Phone';
      case PIIEntityType.address:
        return 'Address';
      case PIIEntityType.ssn:
        return 'SSN';
      case PIIEntityType.creditCard:
        return 'Credit Card';
      case PIIEntityType.date:
        return 'Date';
      case PIIEntityType.other:
        return 'Other';
    }
  }

  /// Returns a color associated with the PII type
  Color get color {
    switch (this) {
      case PIIEntityType.name:
        return Colors.blue;
      case PIIEntityType.email:
        return Colors.green;
      case PIIEntityType.phone:
        return Colors.orange;
      case PIIEntityType.address:
        return Colors.purple;
      case PIIEntityType.ssn:
        return Colors.red;
      case PIIEntityType.creditCard:
        return Colors.pink;
      case PIIEntityType.date:
        return Colors.teal;
      case PIIEntityType.other:
        return Colors.grey;
    }
  }
}
