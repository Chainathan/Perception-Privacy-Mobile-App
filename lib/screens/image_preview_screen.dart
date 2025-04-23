import 'package:flutter/material.dart';
import 'dart:io';
import '../services/model_service.dart';
import 'dart:async';
import 'package:image/image.dart' as img;
import 'dart:ui' as ui;
import '../widgets/mask_overlay_widget.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import 'package:open_file/open_file.dart';
import 'package:image_picker/image_picker.dart';

/// Enum representing the type of image being processed
enum ImageType {
  document,
  nonDocument,
}

/// A screen that displays a preview of a captured or selected image.
/// This screen allows users to confirm the image before processing it.
class ImagePreviewScreen extends StatefulWidget {
  final File imageFile;

  const ImagePreviewScreen({
    super.key,
    required this.imageFile,
  });

  @override
  State<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen> {
  final YoloModelService _modelService = YoloModelService();
  List<Detection>? _detections;
  bool _isProcessing = false;
  String? _errorMessage;
  ui.Image? _baseImage;
  List<MaskOverlay> _maskOverlays = [];
  final GlobalKey _previewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _processImage();
  }

  Future<void> _processImage() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // Load and decode the image
      final loadTimer = Stopwatch()..start();
      debugPrint('Loading image...');
      final imageBytes = await widget.imageFile.readAsBytes();
      final originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) {
        throw Exception('Failed to decode image');
      }
      debugPrint('Image loaded in ${loadTimer.elapsedMilliseconds}ms');
      loadTimer.stop();

      // Convert to ui.Image for display
      final uiImage = await _convertToUiImage(originalImage);
      setState(() {
        _baseImage = uiImage;
      });

      // Run object detection
      final detectionTimer = Stopwatch()..start();
      debugPrint('Running object detection...');
      final detections = await _modelService.detectObjects(widget.imageFile);
      if (detections == null) {
        throw Exception('Failed to detect objects');
      }
      debugPrint(
          'Detection completed in ${detectionTimer.elapsedMilliseconds}ms');
      detectionTimer.stop();

      // Convert detections to mask overlays
      final overlays = await Future.wait(
        detections.map((detection) async {
          if (detection.maskImage == null) return null;
          final uiMask = await _convertToUiImage(detection.maskImage!);
          return MaskOverlay(
            image: uiMask,
            id: detection.id.toString(),
            opacity: 0.5,
            color: detection.color,
          );
        }),
      );

      setState(() {
        _detections = detections;
        _maskOverlays = overlays.whereType<MaskOverlay>().toList();
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isProcessing = false;
      });
      debugPrint('Error processing image: $e');
    }
  }

  Future<ui.Image> _convertToUiImage(img.Image image) async {
    final bytes = img.encodePng(image);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  void _handleMaskTap(String maskId) {
    setState(() {
      _maskOverlays = _maskOverlays.map((overlay) {
        if (overlay.id == maskId) {
          return overlay.copyWith(
            isVisible: !overlay.isVisible,
            displayMode: overlay.displayMode,
          );
        }
        return overlay;
      }).toList();
    });
  }

  Future<void> _saveImage() async {
    if (_baseImage == null) return;

    try {
      setState(() {
        _isProcessing = true;
      });

      // Get the pictures directory for permanent storage
      final directory = await getExternalStorageDirectory();
      if (directory == null)
        throw Exception('Could not access storage directory');

      // Create a 'PerceptionPrivacy' folder in the pictures directory
      final appDir = Directory('${directory.path}/PerceptionPrivacy');
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }

      // Generate a unique filename with timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName =
          'modified_${timestamp}_${path.basename(widget.imageFile.path)}';
      final filePath = path.join(appDir.path, fileName);

      // More efficient approach: start with original image
      final originalImageBytes = await widget.imageFile.readAsBytes();
      final image = img.decodeImage(originalImageBytes);

      if (image == null) throw Exception('Failed to decode image');

      // Apply visible masks directly to the image
      final visibleMasks = _maskOverlays.where((m) => m.isVisible).toList();
      if (visibleMasks.isNotEmpty) {
        for (final mask in visibleMasks) {
          final maskBytes =
              await mask.image.toByteData(format: ui.ImageByteFormat.png);
          if (maskBytes == null) continue;

          final maskImg = img.decodeImage(maskBytes.buffer.asUint8List());
          if (maskImg == null) continue;

          // Calculate scale factor between mask and original image
          final scaleX = image.width / maskImg.width;
          final scaleY = image.height / maskImg.height;

          // Apply mask based on display mode
          switch (mask.displayMode) {
            case MaskDisplayMode.overlay:
              _applyOverlayMaskEfficient(image, maskImg, mask, scaleX, scaleY);
              break;
            case MaskDisplayMode.solid:
              _applySolidMaskEfficient(image, maskImg, mask, scaleX, scaleY);
              break;
            case MaskDisplayMode.blur:
              _applyBlurMaskEfficient(image, maskImg, mask, scaleX, scaleY);
              break;
          }
        }
      }

      // Save the modified image
      final outputFile = File(filePath);
      await outputFile.writeAsBytes(img.encodePng(image));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image saved'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () async {
                try {
                  final result = await OpenFile.open(filePath);
                  if (result.type != ResultType.done) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text('Error opening file: ${result.message}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error opening file: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          ),
        );

        // Show a separate snackbar for the share action
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Share this image?'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Share',
              onPressed: () async {
                try {
                  await Share.shareXFiles(
                    [XFile(filePath)],
                    text: 'Modified image from Perception Privacy',
                  );
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error sharing file: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }
// Optimized methods for applying different mask types

  void _applyOverlayMaskEfficient(img.Image image, img.Image maskImg,
      MaskOverlay overlay, double scaleX, double scaleY) {
    final color = overlay.color ?? Colors.white;
    final r = color.red;
    final g = color.green;
    final b = color.blue;
    final opacity = (255 * overlay.opacity).round();

    // Process mask in chunks to improve performance
    for (var y = 0; y < maskImg.height; y++) {
      final imageY = (y * scaleY).round();
      if (imageY >= image.height) continue;

      for (var x = 0; x < maskImg.width; x++) {
        final imageX = (x * scaleX).round();
        if (imageX >= image.width) continue;

        final maskPixel = maskImg.getPixel(x, y);
        if (maskPixel.a > 0) {
          final origPixel = image.getPixel(imageX, imageY);

          // Blend colors based on overlay opacity
          final newR =
              ((origPixel.r * (255 - opacity) + r * opacity) / 255).round();
          final newG =
              ((origPixel.g * (255 - opacity) + g * opacity) / 255).round();
          final newB =
              ((origPixel.b * (255 - opacity) + b * opacity) / 255).round();

          image.setPixelRgba(imageX, imageY, newR, newG, newB, 255);
        }
      }
    }
  }

  void _applySolidMaskEfficient(img.Image image, img.Image maskImg,
      MaskOverlay overlay, double scaleX, double scaleY) {
    final color = overlay.solidColor ?? overlay.color ?? Colors.white;
    final r = color.red;
    final g = color.green;
    final b = color.blue;

    for (var y = 0; y < maskImg.height; y++) {
      final imageY = (y * scaleY).round();
      if (imageY >= image.height) continue;

      for (var x = 0; x < maskImg.width; x++) {
        final imageX = (x * scaleX).round();
        if (imageX >= image.width) continue;

        final maskPixel = maskImg.getPixel(x, y);
        if (maskPixel.a > 0) {
          image.setPixelRgba(imageX, imageY, r, g, b, 255);
        }
      }
    }
  }

  void _applyBlurMaskEfficient(img.Image image, img.Image maskImg,
      MaskOverlay overlay, double scaleX, double scaleY) {
    // Performance optimization: limit the blur area to just the masked region
    // First, find the bounds of the masked area
    int minX = image.width, maxX = 0, minY = image.height, maxY = 0;
    bool hasMaskedPixels = false;

    for (var y = 0; y < maskImg.height; y++) {
      final imageY = (y * scaleY).round();
      if (imageY >= image.height) continue;

      for (var x = 0; x < maskImg.width; x++) {
        final imageX = (x * scaleX).round();
        if (imageX >= image.width) continue;

        final maskPixel = maskImg.getPixel(x, y);
        if (maskPixel.a > 0) {
          hasMaskedPixels = true;
          minX = imageX < minX ? imageX : minX;
          maxX = imageX > maxX ? imageX : maxX;
          minY = imageY < minY ? imageY : minY;
          maxY = imageY > maxY ? imageY : maxY;
        }
      }
    }

    // If no masked pixels, nothing to do
    if (!hasMaskedPixels) return;

    // Add padding for blur radius
    final blurRadius =
        (overlay.blurStrength * 0.5).round(); // Scale down for performance
    minX = (minX - blurRadius * 2).clamp(0, image.width - 1);
    maxX = (maxX + blurRadius * 2).clamp(0, image.width - 1);
    minY = (minY - blurRadius * 2).clamp(0, image.height - 1);
    maxY = (maxY + blurRadius * 2).clamp(0, image.height - 1);

    // Extract just the region to blur (much smaller than the whole image)
    final regionWidth = maxX - minX + 1;
    final regionHeight = maxY - minY + 1;

    if (regionWidth <= 0 || regionHeight <= 0) return;

    final regionToBlur = img.Image(width: regionWidth, height: regionHeight);

    // Copy the region
    for (var y = 0; y < regionHeight; y++) {
      for (var x = 0; x < regionWidth; x++) {
        final srcX = minX + x;
        final srcY = minY + y;
        regionToBlur.setPixel(x, y, image.getPixel(srcX, srcY));
      }
    }

    // Apply blur to the small region only
    img.gaussianBlur(regionToBlur, radius: blurRadius);

    // Create a mask for just this region
    final regionMask = img.Image(width: regionWidth, height: regionHeight);

    // Transfer the mask to the region coordinates
    for (var y = 0; y < maskImg.height; y++) {
      final imageY = (y * scaleY).round();
      if (imageY < minY || imageY > maxY) continue;

      for (var x = 0; x < maskImg.width; x++) {
        final imageX = (x * scaleX).round();
        if (imageX < minX || imageX > maxX) continue;

        final maskPixel = maskImg.getPixel(x, y);
        if (maskPixel.a > 0) {
          regionMask.setPixelRgba(
              imageX - minX, imageY - minY, 255, 255, 255, 255);
        }
      }
    }

    // Apply the blurred region back to the main image, using the mask
    for (var y = 0; y < regionHeight; y++) {
      final destY = minY + y;
      for (var x = 0; x < regionWidth; x++) {
        final destX = minX + x;
        final maskPixel = regionMask.getPixel(x, y);
        if (maskPixel.a > 0) {
          image.setPixel(destX, destY, regionToBlur.getPixel(x, y));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Preview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isProcessing ? null : _saveImage,
            tooltip: 'Save modified image',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isProcessing) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'Error: $_errorMessage',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _processImage,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_baseImage == null) {
      return const Center(child: Text('No image loaded'));
    }

    return Column(
      children: [
        Expanded(
          child: RepaintBoundary(
            key: _previewKey,
            child: MaskOverlayWidget(
              baseImage: _baseImage!,
              masks: _maskOverlays,
              onMaskTap: _handleMaskTap,
              fit: BoxFit.contain,
            ),
          ),
        ),
        if (_detections != null) ...[
          const SizedBox(height: 16),
          Text(
            'Found ${_detections!.length} objects',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _detections!.length,
              itemBuilder: (context, index) {
                final detection = _detections![index];
                final overlay = _maskOverlays.firstWhere(
                  (o) => o.id == detection.id.toString(),
                  orElse: () => MaskOverlay(
                    image: _baseImage!,
                    id: detection.id.toString(),
                    isVisible: false,
                  ),
                );
                return ListTile(
                  title: Text(detection.className),
                  isThreeLine: true,
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Confidence: ${(detection.confidence * 100).toStringAsFixed(1)}%',
                      ),
                      if (overlay.displayMode == MaskDisplayMode.blur) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Blur: '),
                            Expanded(
                              child: Slider(
                                value: overlay.blurStrength,
                                min: 0,
                                max: 100,
                                divisions: 20,
                                label: overlay.blurStrength.round().toString(),
                                onChanged: (value) {
                                  setState(() {
                                    _maskOverlays = _maskOverlays.map((o) {
                                      if (o.id == overlay.id) {
                                        return o.copyWith(blurStrength: value);
                                      }
                                      return o;
                                    }).toList();
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (overlay.displayMode == MaskDisplayMode.solid) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Color: '),
                            IconButton(
                              icon: Icon(
                                Icons.color_lens,
                                color: overlay.solidColor ??
                                    overlay.color ??
                                    Colors.white,
                              ),
                              onPressed: () {
                                Color pickerColor = overlay.solidColor ??
                                    overlay.color ??
                                    Colors.white;
                                showDialog(
                                  context: context,
                                  barrierDismissible: true,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                      title: const Text('Select Color'),
                                      content: SingleChildScrollView(
                                        child: ColorPicker(
                                          pickerColor: pickerColor,
                                          onColorChanged: (Color color) {
                                            pickerColor = color;
                                          },
                                        ),
                                      ),
                                      actions: <Widget>[
                                        TextButton(
                                          child: const Text('Cancel'),
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                          },
                                        ),
                                        TextButton(
                                          child: const Text('Done'),
                                          onPressed: () {
                                            setState(() {
                                              _maskOverlays =
                                                  _maskOverlays.map((o) {
                                                if (o.id == overlay.id) {
                                                  return o.copyWith(
                                                      solidColor: pickerColor);
                                                }
                                                return o;
                                              }).toList();
                                            });
                                            Navigator.of(context).pop();
                                          },
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Display mode selector
                      DropdownButton<MaskDisplayMode>(
                        value: overlay.displayMode,
                        items: const [
                          DropdownMenuItem(
                            value: MaskDisplayMode.overlay,
                            child: Icon(Icons.visibility),
                          ),
                          DropdownMenuItem(
                            value: MaskDisplayMode.solid,
                            child: Icon(Icons.format_color_fill),
                          ),
                          DropdownMenuItem(
                            value: MaskDisplayMode.blur,
                            child: Icon(Icons.blur_on),
                          ),
                        ],
                        onChanged: (newMode) {
                          if (newMode != null) {
                            setState(() {
                              _maskOverlays = _maskOverlays.map((o) {
                                if (o.id == overlay.id) {
                                  return o.copyWith(displayMode: newMode);
                                }
                                return o;
                              }).toList();
                            });
                          }
                        },
                      ),
                      // Visibility toggle
                      IconButton(
                        icon: Icon(
                          overlay.isVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () => _handleMaskTap(overlay.id),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
