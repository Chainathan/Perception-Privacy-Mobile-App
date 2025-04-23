import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/pii_entity.dart';

/// Service class for interacting with the ChatGPT API
class ChatGPTService {
  /// The API key for authentication
  final String apiKey;

  /// The base URL for the ChatGPT API
  final String baseUrl = 'https://api.openai.com/v1/chat/completions';

  /// Maximum number of retries for failed requests
  static const int maxRetries = 3;

  /// Delay between retries in milliseconds
  static const int retryDelay = 1000;

  /// Creates a new instance of ChatGPTService
  ChatGPTService({required this.apiKey});

  /// Detects PII entities in the given text using ChatGPT
  Future<List<PIIEntity>> detectPII(String text) async {
    try {
      // print the text to analyze
      debugPrint('Text to analyze: $text');
      final response = await makeRequest(
        'The following text has been extracted from a document using OCR (Optical Character Recognition). '
        'Please analyze it and identify any Personally Identifiable Information (PII), taking into account potential OCR artifacts or formatting issues. '
        'Return ONLY a JSON array containing all detected PII entities. Each entity should follow this structure:\n'
        '[\n'
        '  {\n'
        '    "text": "the exact PII text found",\n'
        '    "type": "name|email|phone|address|ssn|creditCard|date|other",\n'
        '    "start_index": starting position in text (number),\n'
        '    "end_index": ending position in text (number),\n'
        '    "confidence": confidence score between 0 and 1 (number)\n'
        '  }\n'
        ']\n\n'
        'Important Indexing Rules:\n'
        '1. Indices are zero-based (first character is at index 0)\n'
        '2. start_index is inclusive (includes the first character)\n'
        '3. end_index is exclusive (does not include the last character)\n'
        '4. For multi-line text, newlines (\\n) count as a single character\n'
        '5. Indices must be exact and match the exact text found\n\n'
        'Example:\n'
        'For the text: "Customer Information:\\nName: John Smith\\nAddress: 123 Main St, Apt 4B\\nContact: (555) 123-4567\\nEmail: john@email.com\\nThank you for your business!"\n'
        'The correct indices would be:\n'
        '{\n'
        '  "text": "John Smith",\n'
        '  "type": "name",\n'
        '  "start_index": 20,\n'
        '  "end_index": 29,\n'
        '  "confidence": 0.95\n'
        '},\n'
        '{\n'
        '  "text": "123 Main St, Apt 4B",\n'
        '  "type": "address",\n'
        '  "start_index": 38,\n'
        '  "end_index": 56,\n'
        '  "confidence": 0.9\n'
        '},\n'
        '{\n'
        '  "text": "(555) 123-4567",\n'
        '  "type": "phone",\n'
        '  "start_index": 65,\n'
        '  "end_index": 79,\n'
        '  "confidence": 0.95\n'
        '},\n'
        '{\n'
        '  "text": "john@email.com",\n'
        '  "type": "email",\n'
        '  "start_index": 86,\n'
        '  "end_index": 100,\n'
        '  "confidence": 0.98\n'
        '}\n\n'
        'Text to analyze:\n"""\n$text\n"""',
      );

      return _parsePIIResponse(response);
    } catch (e) {
      debugPrint('Error detecting PII: $e');
      rethrow;
    }
  }

  /// Masks PII entities in the given text
  Future<String> maskPII(String text, List<PIIEntity> entities) async {
    try {
      String maskedText = text;

      // Sort entities by end index in descending order to avoid index shifting
      final sortedEntities = List<PIIEntity>.from(entities)
        ..sort((a, b) => b.endIndex.compareTo(a.endIndex));

      for (final entity in sortedEntities) {
        final replacement = _getMaskReplacement(entity.type);
        maskedText = maskedText.replaceRange(
          entity.startIndex,
          entity.endIndex,
          replacement,
        );
      }

      return maskedText;
    } catch (e) {
      debugPrint('Error masking PII: $e');
      rethrow;
    }
  }

  /// Makes a request to the ChatGPT API with retry logic
  Future<String> makeRequest(String prompt) async {
    debugPrint('Making request to ChatGPT with prompt: $prompt');
    int retries = 0;
    while (retries < maxRetries) {
      try {
        final response = await http.post(
          Uri.parse(
              'https://api.openai.com/v1/completions'), // Different endpoint for instruct model
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': 'gpt-3.5-turbo-instruct',
            'prompt': 'You are a PII detection assistant. Your task is to analyze text and identify Personally Identifiable Information (PII). '
                'You must return ONLY a valid JSON array containing all detected PII entities. Do not include any other text or explanation. '
                'Each entity must include the exact text found, its type, start and end indices, and a confidence score.\n\n'
                '$prompt',
            'temperature': 0.1,
            'max_tokens': 3000,
          }),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          debugPrint('ChatGPT response: $data');
          final content = data['choices'][0]['text'];
          return content;
        } else {
          throw Exception(
              'API request failed: ${response.statusCode} - ${response.body}');
        }
      } catch (e) {
        retries++;
        if (retries == maxRetries) {
          rethrow;
        }
        await Future.delayed(Duration(milliseconds: retryDelay * retries));
      }
    }
    throw Exception('Max retries exceeded');
  }

  /// Parses the ChatGPT API response into a list of PIIEntity objects
  List<PIIEntity> _parsePIIResponse(String response) {
    try {
      // debugPrint('Parsing response: $response'); // For debugging

      // Try to parse the response directly as JSON
      final dynamic jsonData = jsonDecode(response);

      // If the response is a JSON object with a 'results' or 'entities' field, use that
      final List<dynamic> jsonList = jsonData is List
          ? jsonData
          : (jsonData['results'] ?? jsonData['entities'] ?? []);

      return jsonList
          .map((json) {
            // Ensure all required fields are present
            if (!json.containsKey('text') ||
                !json.containsKey('type') ||
                !json.containsKey('start_index') ||
                !json.containsKey('end_index')) {
              debugPrint('Invalid entity format: $json');
              return null;
            }

            try {
              return PIIEntity(
                text: json['text'] as String,
                type: _parseEntityType(json['type'] as String),
                startIndex: json['start_index'] as int,
                endIndex: json['end_index'] as int,
                confidence: (json['confidence'] ?? 0.8) as double,
              );
            } catch (e) {
              debugPrint('Error parsing entity: $e');
              return null;
            }
          })
          .where((entity) => entity != null)
          .cast<PIIEntity>()
          .toList();
    } catch (e) {
      debugPrint('Error parsing PII response: $e');
      rethrow;
    }
  }

  /// Parses a string into a PIIEntityType
  PIIEntityType _parseEntityType(String type) {
    final normalizedType = type.toLowerCase().trim();
    switch (normalizedType) {
      case 'name':
        return PIIEntityType.name;
      case 'email':
        return PIIEntityType.email;
      case 'phone':
        return PIIEntityType.phone;
      case 'address':
        return PIIEntityType.address;
      case 'ssn':
        return PIIEntityType.ssn;
      case 'creditcard':
      case 'credit_card':
      case 'credit card':
        return PIIEntityType.creditCard;
      case 'date':
        return PIIEntityType.date;
      default:
        return PIIEntityType.other;
    }
  }

  /// Returns the appropriate mask replacement for a given PII type
  String _getMaskReplacement(PIIEntityType type) {
    switch (type) {
      case PIIEntityType.name:
        return '[NAME]';
      case PIIEntityType.email:
        return '[EMAIL]';
      case PIIEntityType.phone:
        return '[PHONE]';
      case PIIEntityType.address:
        return '[ADDRESS]';
      case PIIEntityType.ssn:
        return '[SSN]';
      case PIIEntityType.creditCard:
        return '[CC]';
      case PIIEntityType.date:
        return '[DATE]';
      case PIIEntityType.other:
        return '[PII]';
    }
  }
}
