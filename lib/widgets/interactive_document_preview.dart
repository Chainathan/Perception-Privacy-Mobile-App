import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import '../models/text_block_with_pii.dart';
import '../models/text_element_with_pii.dart';
import '../models/pii_entity.dart';
import 'package:image/image.dart' as img;

class InteractiveDocumentPreview extends StatefulWidget {
  final File imageFile;
  final List<TextBlockWithPII> textBlocks;
  final Color maskColor;
  final bool showBoundingBoxes;
  final bool showAllWords;
  final Set<PIIEntityType> selectedPIITypes;
  final bool applyMasking;
  final Function(Size)? onImageSize;

  const InteractiveDocumentPreview({
    Key? key,
    required this.imageFile,
    required this.textBlocks,
    required this.maskColor,
    this.showBoundingBoxes = true,
    this.showAllWords = false,
    this.selectedPIITypes = const {},
    this.applyMasking = false,
    this.onImageSize,
  }) : super(key: key);

  @override
  State<InteractiveDocumentPreview> createState() =>
      _InteractiveDocumentPreviewState();
}

class _InteractiveDocumentPreviewState
    extends State<InteractiveDocumentPreview> {
  final TransformationController _transformationController =
      TransformationController();
  final ValueNotifier<Size?> _imageSizeNotifier = ValueNotifier<Size?>(null);
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _getImageSize();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _imageSizeNotifier.dispose();
    super.dispose();
  }

  Future<void> _getImageSize() async {
    try {
      final bytes = await widget.imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image != null) {
        _imageSizeNotifier.value = Size(
          image.width.toDouble(),
          image.height.toDouble(),
        );
        if (widget.onImageSize != null) {
          widget.onImageSize!(_imageSizeNotifier.value!);
        }
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading image: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return InteractiveViewer(
          transformationController: _transformationController,
          minScale: 0.5,
          maxScale: 4.0,
          child: Stack(
            children: [
              Image.file(
                widget.imageFile,
                fit: BoxFit.contain,
                width: constraints.maxWidth,
                height: constraints.maxHeight,
              ),

              // Bounding boxes and masking overlay
              ValueListenableBuilder<Size?>(
                valueListenable: _imageSizeNotifier,
                builder: (context, imageSize, child) {
                  if (imageSize == null) return const SizedBox();
                  return CustomPaint(
                    size: Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    ),
                    painter: BoundingBoxPainter(
                      textBlocks: widget.textBlocks,
                      imageSize: imageSize,
                      containerSize: Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      ),
                      showAllWords: widget.showAllWords,
                      selectedPIITypes: widget.selectedPIITypes,
                      applyMasking: widget.applyMasking,
                      maskColor: widget.maskColor,
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getPIIColor(PIIEntityType piiType) {
    switch (piiType) {
      case PIIEntityType.name:
        return const Color(0xFFFF5252);
      case PIIEntityType.email:
        return const Color(0xFF2196F3);
      case PIIEntityType.phone:
        return const Color(0xFF4CAF50);
      case PIIEntityType.address:
        return const Color(0xFFFF9800);
      case PIIEntityType.ssn:
        return const Color(0xFF9C27B0);
      case PIIEntityType.creditCard:
        return const Color(0xFFE91E63);
      case PIIEntityType.date:
        return const Color(0xFF009688);
      default:
        return const Color(0xFF607D8B);
    }
  }
}

class BoundingBoxPainter extends CustomPainter {
  final List<TextBlockWithPII> textBlocks;
  final Size imageSize;
  final Size containerSize;
  final bool showAllWords;
  final Set<PIIEntityType> selectedPIITypes;
  final bool applyMasking;
  final Color maskColor;

  BoundingBoxPainter({
    required this.textBlocks,
    required this.imageSize,
    required this.containerSize,
    required this.showAllWords,
    required this.selectedPIITypes,
    required this.applyMasking,
    required this.maskColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Calculate the scaling factor to fit the image in the container
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;
    final scaleFactor = scaleX < scaleY ? scaleX : scaleY;

    // Calculate the offset to center the image
    final offsetX = (size.width - (imageSize.width * scaleFactor)) / 2;
    final offsetY = (size.height - (imageSize.height * scaleFactor)) / 2;

    for (final block in textBlocks) {
      for (final element in block.elementsWithPII) {
        // Only process if it's a word-level box or has PII
        if (showAllWords || element.hasPII) {
          // Get the bounding box coordinates
          final rect = element.boundingBox;

          // Scale and translate the coordinates
          final scaledRect = Rect.fromLTWH(
            (rect.left * scaleFactor) + offsetX,
            (rect.top * scaleFactor) + offsetY,
            rect.width * scaleFactor,
            rect.height * scaleFactor,
          );

          // Draw the bounding box or mask
          if (element.hasPII) {
            final piiType = element.primaryPIIType;
            if (piiType != null && selectedPIITypes.contains(piiType)) {
              if (applyMasking) {
                // Draw mask
                paint
                  ..style = PaintingStyle.fill
                  ..color = maskColor;
                canvas.drawRect(scaledRect, paint);
              } else {
                // Draw bounding box
                paint
                  ..style = PaintingStyle.stroke
                  ..color = _getPIIColor(piiType);
                canvas.drawRect(scaledRect, paint);
              }
            }
          } else if (showAllWords) {
            // Draw word-level box in blue
            paint
              ..style = PaintingStyle.stroke
              ..color = Colors.blue.withOpacity(0.7);
            canvas.drawRect(scaledRect, paint);
          }
        }
      }
    }
  }

  Color _getPIIColor(PIIEntityType piiType) {
    switch (piiType) {
      case PIIEntityType.name:
        return const Color(0xFFFF5252);
      case PIIEntityType.email:
        return const Color(0xFF2196F3);
      case PIIEntityType.phone:
        return const Color(0xFF4CAF50);
      case PIIEntityType.address:
        return const Color(0xFFFF9800);
      case PIIEntityType.ssn:
        return const Color(0xFF9C27B0);
      case PIIEntityType.creditCard:
        return const Color(0xFFE91E63);
      case PIIEntityType.date:
        return const Color(0xFF009688);
      default:
        return const Color(0xFF607D8B);
    }
  }

  @override
  bool shouldRepaint(BoundingBoxPainter oldDelegate) {
    return textBlocks != oldDelegate.textBlocks ||
        showAllWords != oldDelegate.showAllWords ||
        selectedPIITypes != oldDelegate.selectedPIITypes ||
        applyMasking != oldDelegate.applyMasking ||
        maskColor != oldDelegate.maskColor;
  }
}
