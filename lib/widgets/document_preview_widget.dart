import 'package:flutter/material.dart';
import '../models/text_block_with_pii.dart';
import '../models/pii_entity.dart';
import '../models/text_element_with_pii.dart';

/// Widget to display OCR results with PII detection
class DocumentPreviewWidget extends StatelessWidget {
  /// List of text blocks with PII information
  final List<TextBlockWithPII> textBlocks;

  /// Callback when a text block is selected
  final Function(TextBlockWithPII)? onBlockSelected;

  /// Callback when a text block is deselected
  final Function(TextBlockWithPII)? onBlockDeselected;

  /// Callback when a text element is selected
  final Function(TextElementWithPII)? onElementSelected;

  /// Callback when a text element is deselected
  final Function(TextElementWithPII)? onElementDeselected;

  /// Creates a new DocumentPreviewWidget
  const DocumentPreviewWidget({
    Key? key,
    required this.textBlocks,
    this.onBlockSelected,
    this.onBlockDeselected,
    this.onElementSelected,
    this.onElementDeselected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Document Text with PII Detection',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ...textBlocks.map((block) => _buildTextBlock(context, block)),
          ],
        ),
      ),
    );
  }

  /// Builds a text block with PII highlighting
  Widget _buildTextBlock(BuildContext context, TextBlockWithPII block) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () {
          if (block.isSelected) {
            onBlockDeselected?.call(block);
          } else {
            onBlockSelected?.call(block);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Block-level text with PII highlighting
              _buildTextWithPII(context, block),

              if (block.detectedPII.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildPIILegend(context, block.detectedPII),
              ],

              // Word-level PII display
              if (block.elementsWithPII.any((e) => e.hasPII)) ...[
                const SizedBox(height: 16),
                Text(
                  'Word-level PII:',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: block.elementsWithPII
                      .where((e) => e.hasPII)
                      .map((element) => _buildWordElement(context, element))
                      .toList(),
                ),
              ],

              const SizedBox(height: 8),
              Text(
                'Bounding Box: ${block.boundingBox.toString()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds text with PII highlighting
  Widget _buildTextWithPII(BuildContext context, TextBlockWithPII block) {
    if (block.detectedPII.isEmpty) {
      return Text(block.text);
    }

    // Sort PII entities by start index
    final sortedPII = List<PIIEntity>.from(block.detectedPII)
      ..sort((a, b) => a.startIndex.compareTo(b.startIndex));

    // Create text spans with PII highlighting
    final spans = <TextSpan>[];
    var currentIndex = 0;

    for (final pii in sortedPII) {
      // Add text before PII
      if (pii.startIndex > currentIndex) {
        spans.add(TextSpan(
          text: block.text.substring(currentIndex, pii.startIndex),
        ));
      }

      // Add PII text with highlighting
      spans.add(TextSpan(
        text: block.text.substring(pii.startIndex, pii.endIndex),
        style: TextStyle(
          backgroundColor: _getPIIColor(pii.type),
          fontWeight: FontWeight.bold,
        ),
      ));

      currentIndex = pii.endIndex;
    }

    // Add remaining text
    if (currentIndex < block.text.length) {
      spans.add(TextSpan(
        text: block.text.substring(currentIndex),
      ));
    }

    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: spans,
      ),
    );
  }

  /// Builds a word element with PII highlighting
  Widget _buildWordElement(BuildContext context, TextElementWithPII element) {
    return InkWell(
      onTap: () {
        if (element.isSelected) {
          onElementDeselected?.call(element);
        } else {
          onElementSelected?.call(element);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: element.hasPII
              ? _getPIIColor(element.primaryPIIType!).withOpacity(0.2)
              : null,
          border: Border.all(
            color: element.hasPII
                ? _getPIIColor(element.primaryPIIType!)
                : Colors.grey,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              element.text,
              style: TextStyle(
                fontWeight:
                    element.hasPII ? FontWeight.bold : FontWeight.normal,
                color: element.hasPII
                    ? _getPIIColor(element.primaryPIIType!)
                    : Colors.black,
              ),
            ),
            if (element.hasPII) ...[
              const SizedBox(height: 4),
              Text(
                element.detectedPII.map((e) => e.type.toString()).join(', '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Builds a legend showing PII types in the block
  Widget _buildPIILegend(BuildContext context, List<PIIEntity> piiEntities) {
    // Get unique PII types
    final piiTypes = piiEntities.map((e) => e.type).toSet().toList();

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: piiTypes.map((type) {
        return Chip(
          label: Text(type.toString()),
          backgroundColor: _getPIIColor(type).withOpacity(0.2),
          labelStyle: TextStyle(color: _getPIIColor(type)),
        );
      }).toList(),
    );
  }

  /// Gets color for PII type
  Color _getPIIColor(PIIEntityType type) {
    switch (type) {
      case PIIEntityType.name:
        return Colors.red;
      case PIIEntityType.email:
        return Colors.blue;
      case PIIEntityType.phone:
        return Colors.green;
      case PIIEntityType.address:
        return Colors.orange;
      case PIIEntityType.ssn:
        return Colors.purple;
      case PIIEntityType.creditCard:
        return Colors.indigo;
      case PIIEntityType.date:
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }
}
