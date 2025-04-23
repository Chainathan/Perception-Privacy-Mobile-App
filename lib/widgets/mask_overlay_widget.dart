import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;

/// Enum representing the different ways a mask can be displayed
enum MaskDisplayMode {
  overlay, // Semi-transparent overlay (default)
  solid, // Solid color infill
  blur, // Blurred effect on the underlying image
}

/// A class representing a single mask overlay with its properties
class MaskOverlay {
  final ui.Image image;
  final double opacity;
  final Color? color;
  final String id;
  final bool isVisible;
  final MaskDisplayMode displayMode;
  final double blurStrength; // New property for blur strength
  final Color? solidColor; // New property for custom solid color

  const MaskOverlay({
    required this.image,
    required this.id,
    this.opacity = 0.5,
    this.color,
    this.isVisible = true,
    this.displayMode = MaskDisplayMode.overlay,
    this.blurStrength = 50.0, // Default blur strength
    this.solidColor, // Optional custom solid color
  });

  MaskOverlay copyWith({
    ui.Image? image,
    double? opacity,
    Color? color,
    String? id,
    bool? isVisible,
    MaskDisplayMode? displayMode,
    double? blurStrength,
    Color? solidColor,
  }) {
    return MaskOverlay(
      image: image ?? this.image,
      opacity: opacity ?? this.opacity,
      color: color ?? this.color,
      id: id ?? this.id,
      isVisible: isVisible ?? this.isVisible,
      displayMode: displayMode ?? this.displayMode,
      blurStrength: blurStrength ?? this.blurStrength,
      solidColor: solidColor ?? this.solidColor,
    );
  }
}

/// A widget that displays an image with multiple mask overlays.
/// Supports opacity, color tinting, and click detection for individual masks.
class MaskOverlayWidget extends StatefulWidget {
  final ui.Image baseImage;
  final List<MaskOverlay> masks;
  final Function(String maskId)? onMaskTap;
  final BoxFit fit;

  const MaskOverlayWidget({
    super.key,
    required this.baseImage,
    required this.masks,
    this.onMaskTap,
    this.fit = BoxFit.contain,
  });

  @override
  State<MaskOverlayWidget> createState() => _MaskOverlayWidgetState();
}

class _MaskOverlayWidgetState extends State<MaskOverlayWidget> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // We draw everything in a single CustomPaint to handle proper layering for blur
        CustomPaint(
          painter: _CombinedPainter(
            baseImage: widget.baseImage,
            masks: widget.masks.where((mask) => mask.isVisible).toList(),
            fit: widget.fit,
          ),
          size: Size.infinite,
        ),

        // Invisible detection layer for handling taps
        ...widget.masks.where((mask) => mask.isVisible).map((mask) {
          return Positioned.fill(
            child: GestureDetector(
              onTapDown: (details) async {
                // Convert tap position to local coordinates
                final RenderBox box = context.findRenderObject() as RenderBox;
                final localPosition = box.globalToLocal(details.globalPosition);

                // Check if tap is within the mask's bounds
                if (await _isTapWithinMask(localPosition, mask)) {
                  widget.onMaskTap?.call(mask.id);
                }
              },
              child: Container(
                color: Colors.transparent, // Invisible but detects taps
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Future<bool> _isTapWithinMask(Offset tapPosition, MaskOverlay mask) async {
    // Get the mask's image data
    final imageData = await mask.image.toByteData();
    if (imageData == null) return false;

    // Calculate the scale factor between the widget size and image size
    final RenderBox box = context.findRenderObject() as RenderBox;
    final widgetSize = box.size;
    final scaleX = widgetSize.width / mask.image.width;
    final scaleY = widgetSize.height / mask.image.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    // Calculate the offset to center the image
    final offsetX = (widgetSize.width - (mask.image.width * scale)) / 2;
    final offsetY = (widgetSize.height - (mask.image.height * scale)) / 2;

    // Convert tap position to image coordinates
    final imageX = ((tapPosition.dx - offsetX) / scale).round();
    final imageY = ((tapPosition.dy - offsetY) / scale).round();

    // Check if the tap is within the image bounds
    if (imageX < 0 ||
        imageX >= mask.image.width ||
        imageY < 0 ||
        imageY >= mask.image.height) {
      return false;
    }

    // Check if the pixel at the tap position is not transparent
    final pixelIndex = (imageY * mask.image.width + imageX) * 4;
    final alpha = imageData.getUint8(pixelIndex + 3);
    return alpha > 0;
  }
}

/// A custom painter that draws the base image and all masks with proper layering
class _CombinedPainter extends CustomPainter {
  final ui.Image baseImage;
  final List<MaskOverlay> masks;
  final BoxFit fit;

  _CombinedPainter({
    required this.baseImage,
    required this.masks,
    required this.fit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate scale and offset for proper image fitting
    final imageSize = Size(
      baseImage.width.toDouble(),
      baseImage.height.toDouble(),
    );

    final scale = _calculateScale(imageSize, size, fit);
    final offset = _calculateOffset(imageSize, size, scale, fit);

    // Save the canvas state so we can restore it later
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    // First draw the base image
    canvas.drawImage(baseImage, Offset.zero, Paint());

    // Then draw each mask according to its display mode
    for (final mask in masks) {
      switch (mask.displayMode) {
        case MaskDisplayMode.overlay:
          _drawOverlay(canvas, mask);
          break;
        case MaskDisplayMode.solid:
          _drawSolid(canvas, mask);
          break;
        case MaskDisplayMode.blur:
          _drawBlur(canvas, mask, imageSize);
          break;
      }
    }

    // Restore canvas state
    canvas.restore();
  }

  double _calculateScale(Size imageSize, Size containerSize, BoxFit fit) {
    switch (fit) {
      case BoxFit.contain:
        final scaleX = containerSize.width / imageSize.width;
        final scaleY = containerSize.height / imageSize.height;
        return scaleX < scaleY ? scaleX : scaleY;
      case BoxFit.cover:
        final scaleX = containerSize.width / imageSize.width;
        final scaleY = containerSize.height / imageSize.height;
        return scaleX > scaleY ? scaleX : scaleY;
      case BoxFit.fill:
        return Size(
          containerSize.width / imageSize.width,
          containerSize.height / imageSize.height,
        ).aspectRatio;
      case BoxFit.fitWidth:
        return containerSize.width / imageSize.width;
      case BoxFit.fitHeight:
        return containerSize.height / imageSize.height;
      case BoxFit.none:
        return 1.0;
      case BoxFit.scaleDown:
        final scaleX = containerSize.width / imageSize.width;
        final scaleY = containerSize.height / imageSize.height;
        final scale = scaleX < scaleY ? scaleX : scaleY;
        return scale < 1.0 ? scale : 1.0;
    }
  }

  Offset _calculateOffset(
      Size imageSize, Size containerSize, double scale, BoxFit fit) {
    final scaledImageSize = Size(
      imageSize.width * scale,
      imageSize.height * scale,
    );

    double dx = 0;
    double dy = 0;

    switch (fit) {
      case BoxFit.contain:
      case BoxFit.cover:
      case BoxFit.scaleDown:
        dx = (containerSize.width - scaledImageSize.width) / 2;
        dy = (containerSize.height - scaledImageSize.height) / 2;
        break;
      case BoxFit.fill:
      case BoxFit.fitWidth:
      case BoxFit.fitHeight:
      case BoxFit.none:
        dx = 0;
        dy = 0;
        break;
    }

    return Offset(dx, dy);
  }

  void _drawOverlay(Canvas canvas, MaskOverlay mask) {
    final paint = Paint()
      ..colorFilter = ColorFilter.mode(
        mask.color?.withOpacity(mask.opacity) ??
            Colors.white.withOpacity(mask.opacity),
        BlendMode.srcIn,
      );
    canvas.drawImage(mask.image, Offset.zero, paint);
  }

  void _drawSolid(Canvas canvas, MaskOverlay mask) {
    final paint = Paint()
      ..colorFilter = ColorFilter.mode(
        mask.solidColor ?? mask.color ?? Colors.white,
        BlendMode.srcIn,
      );
    canvas.drawImage(mask.image, Offset.zero, paint);
  }

  void _drawBlur(Canvas canvas, MaskOverlay mask, Size imageSize) {
    final clipRect = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);

    // Create a layer for the mask that will act as a clip
    canvas.saveLayer(clipRect, Paint());

    // Draw the mask to create our clip area
    canvas.drawImage(mask.image, Offset.zero, Paint()..color = Colors.white);

    // Setup the blending mode to only affect areas where mask pixels exist
    canvas.saveLayer(clipRect, Paint()..blendMode = BlendMode.srcIn);

    // Apply the blur to the area
    canvas.saveLayer(
        clipRect,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: mask.blurStrength,
            sigmaY: mask.blurStrength,
            tileMode: TileMode.decal,
          ));

    // Draw the original image again (this will be blurred where the mask exists)
    canvas.drawImage(baseImage, Offset.zero, Paint());

    // Restore all canvas states
    canvas.restore(); // Blur layer
    canvas.restore(); // Alpha mask layer
    canvas.restore(); // Clip layer
  }

  @override
  bool shouldRepaint(_CombinedPainter oldDelegate) {
    return baseImage != oldDelegate.baseImage ||
        masks != oldDelegate.masks ||
        fit != oldDelegate.fit;
  }
}
