import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A 2D matrix implementation using Float32List for efficient memory usage
/// while providing intuitive 2D access patterns.
class Matrix2D {
  final Float32List data;
  final int width;
  final int height;

  Matrix2D(this.width, this.height) : data = Float32List(width * height);

  /// Creates a Matrix2D filled with a specific value
  Matrix2D.filled(this.width, this.height, double value)
      : data = Float32List(width * height)..fillRange(0, width * height, value);

  /// Gets the value at (x, y)
  double get(int x, int y) => data[y * width + x];

  /// Sets the value at (x, y)
  void set(int x, int y, double value) => data[y * width + x] = value;

  /// Fills a region of the matrix with a value
  void fillRegion(int startX, int startY, int endX, int endY, double value) {
    for (var y = startY; y < endY; y++) {
      if (y < 0 || y >= height) continue;
      for (var x = startX; x < endX; x++) {
        if (x < 0 || x >= width) continue;
        set(x, y, value);
      }
    }
  }

  /// Applies a function to each element in a region
  void applyRegion(
      int startX, int startY, int endX, int endY, double Function(double) fn) {
    for (var y = startY; y < endY; y++) {
      if (y < 0 || y >= height) continue;
      for (var x = startX; x < endX; x++) {
        if (x < 0 || x >= width) continue;
        set(x, y, fn(get(x, y)));
      }
    }
  }

  /// Creates a copy of this matrix
  Matrix2D copy() {
    final result = Matrix2D(width, height);
    result.data.setAll(0, data);
    return result;
  }
}

class YoloModelService {
  Interpreter? _interpreter;
  List<String>? _labels;
  final int _inputSize = 640; // Pretrained model input size

  YoloModelService() {
    _loadModel();
    _loadLabels();
  }

  Future<void> _loadModel() async {
    try {
      final options = InterpreterOptions();
      _interpreter =
          await Interpreter.fromAsset('assets/model.tflite', options: options);
      _interpreter!.allocateTensors();
    } catch (e) {
      print("Error loading model: $e");
    }
  }

  Future<void> _loadLabels() async {
    try {
      final labelData = await rootBundle.loadString('assets/labels.txt');
      _labels = labelData.split('\n');
      debugPrint('labels length: ${_labels!.length}');
    } catch (e) {
      print("Error loading labels: $e");
    }
  }

  Future<List<Detection>?> detectObjects(File imageFile) async {
    if (_interpreter == null || _labels == null) {
      print("Model or labels not loaded");
      return null;
    }

    final stopwatch = Stopwatch()..start();
    debugPrint('Starting object detection pipeline...');

    // Load and preprocess the image
    final loadTimer = Stopwatch()..start();
    img.Image? image = img.decodeImage(await imageFile.readAsBytes());
    if (image == null) return null;
    debugPrint('Image loaded in ${loadTimer.elapsedMilliseconds}ms');
    loadTimer.stop();

    var originalHeight = image.height;
    var originalWidth = image.width;
    debugPrint('Original image size: ${image.width}x${image.height}');

    // Resize image
    final resizeTimer = Stopwatch()..start();
    image = img.copyResize(image, width: _inputSize, height: _inputSize);
    debugPrint('Image resized in ${resizeTimer.elapsedMilliseconds}ms');
    resizeTimer.stop();

    // Convert to input tensor
    final convertTimer = Stopwatch()..start();
    var input = imageToByteListFloat32(image, _inputSize);
    debugPrint(
        'Image converted to tensor in ${convertTimer.elapsedMilliseconds}ms');
    convertTimer.stop();

    // Define output buffers
    final bufferTimer = Stopwatch()..start();
    var outputShapes = _interpreter!.getOutputTensor(0).shape;
    var output = List.generate(
        outputShapes[0],
        (index) => List.generate(outputShapes[1],
            (index) => List.generate(outputShapes[2], (index) => 0.0)));

    var outputShapes1 = _interpreter!.getOutputTensor(1).shape;
    var output1 = List.generate(
        outputShapes1[0],
        (i) => List.generate(
            outputShapes1[1],
            (j) => List.generate(
                outputShapes1[2], (k) => List.filled(outputShapes1[3], 0.0))));
    debugPrint(
        'Output buffers created in ${bufferTimer.elapsedMilliseconds}ms');
    bufferTimer.stop();

    Map<int, Object> outputs = {
      0: output,
      1: output1,
    };

    // Run inference
    final inferenceTimer = Stopwatch()..start();
    debugPrint('Starting model inference...');
    _interpreter!.runForMultipleInputs([input], outputs);
    debugPrint(
        'Model inference completed in ${inferenceTimer.elapsedMilliseconds}ms');
    inferenceTimer.stop();

    // Process output
    final processTimer = Stopwatch()..start();
    debugPrint('Starting postprocessing...');
    final detections = _processOutput(output.first, output1.first,
        originalWidth: originalWidth, originalHeight: originalHeight);
    debugPrint(
        'Postprocessing completed in ${processTimer.elapsedMilliseconds}ms');
    processTimer.stop();

    debugPrint(
        'Total object detection time: ${stopwatch.elapsedMilliseconds}ms');
    stopwatch.stop();

    return detections;
  }

  Uint8List imageToByteListFloat32(img.Image image, int inputSize) {
    var convertedBytes = Float32List(1 * inputSize * inputSize * 3);
    var buffer = Float32List.view(convertedBytes.buffer);
    int pixelIndex = 0;
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        var pixel = image.getPixel(x, y);
        buffer[pixelIndex++] = pixel.r / 255.0; // Red component
        buffer[pixelIndex++] = pixel.g / 255.0; // Green component
        buffer[pixelIndex++] = pixel.b / 255.0; // Blue component
      }
    }
    return convertedBytes.buffer.asUint8List();
  }

  /// Converts a Matrix2D mask to an image with specified color and opacity
  /// If color is null, uses white with full opacity for mask values > 0.5
  /// If color is provided, uses the specified color with the given opacity for mask values > 0.5
  img.Image maskToImage(
    Matrix2D mask, {
    Color? color,
    double opacity = 1.0,
  }) {
    final width = mask.width;
    final height = mask.height;

    // Create a buffer for RGBA values (4 bytes per pixel)
    final buffer = Uint8List(width * height * 4);

    // Fill buffer with colored pixels where mask is 1, transparent where mask is 0
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        final offset = i * 4;

        if (mask.get(x, y) > 0.5) {
          if (color != null) {
            // Use specified color with given opacity
            buffer[offset] = color.red; // R
            buffer[offset + 1] = color.green; // G
            buffer[offset + 2] = color.blue; // B
            buffer[offset + 3] = (opacity * 255).round(); // A
          } else {
            // Default: white with full opacity
            buffer[offset] = 255; // R
            buffer[offset + 1] = 255; // G
            buffer[offset + 2] = 255; // B
            buffer[offset + 3] = 255; // A
          }
        } else {
          // Transparent pixel
          buffer[offset] = 0; // R
          buffer[offset + 1] = 0; // G
          buffer[offset + 2] = 0; // B
          buffer[offset + 3] = 0; // A
        }
      }
    }

    // Create image from buffer
    return img.Image.fromBytes(
      width: width,
      height: height,
      bytes: buffer.buffer,
      numChannels: 4,
    );
  }

  /// Changes the color of non-transparent pixels in an image
  /// while maintaining their original opacity
  // img.Image changeImageColor(
  //   img.Image image, {
  //   required Color newColor,
  //   double opacity = 1.0,
  // }) {
  //   final result = img.Image(width: image.width, height: image.height);

  //   for (var y = 0; y < image.height; y++) {
  //     for (var x = 0; x < image.width; x++) {
  //       final pixel = image.getPixel(x, y);
  //       if (pixel.a > 0) {
  //         // If pixel is not transparent
  //         // Use new color but maintain original alpha
  //         final alpha = (pixel.a * opacity).round();
  //         result.setPixelRgba(
  //           x,
  //           y,
  //           newColor.red,
  //           newColor.green,
  //           newColor.blue,
  //           alpha,
  //         );
  //       } else {
  //         // Keep transparent pixels as is
  //         result.setPixelRgba(x, y, 0, 0, 0, 0);
  //       }
  //     }
  //   }

  //   return result;
  // }

  List<Detection> _processOutput(
      List<List<double>> output, List<List<List<double>>> protoMasks,
      {required int originalWidth, required int originalHeight}) {
    final stopwatch = Stopwatch()..start();
    List<Detection> detections = [];
    int detectionId = 0;

    // Constants for mask dimensions
    const int maskWidth = 160;
    const int maskHeight = 160;

    for (var i = 0; i < output.length; i++) {
      var x1 = output[i][0] * originalWidth;
      var y1 = output[i][1] * originalHeight;
      var x2 = output[i][2] * originalWidth;
      var y2 = output[i][3] * originalHeight;
      var confidence = output[i][4];
      var classIndex = output[i][5].toInt();

      if (confidence > 0.1 &&
          classIndex >= 0 &&
          classIndex < (_labels?.length ?? 0)) {
        debugPrint("ClassIndex: $classIndex Detected ${_labels![classIndex]}");
        debugPrint(
            "Confidence ${confidence.toStringAsFixed(3)} at (${x1.toStringAsFixed(1)}, ${y1.toStringAsFixed(1)}, ${x2.toStringAsFixed(1)}, ${y2.toStringAsFixed(1)})");

        // Scale bounding box coordinates to mask dimensions (160x160)
        final scaledX1 = (x1 / originalWidth * maskWidth).floor();
        final scaledY1 = (y1 / originalHeight * maskHeight).floor();
        final scaledX2 = (x2 / originalWidth * maskWidth).ceil();
        final scaledY2 = (y2 / originalHeight * maskHeight).ceil();

        // Process mask coefficients
        List<double> maskCoeffs = output[i].sublist(6, 38);

        // Generate instance mask using Matrix2D
        final mask160 = Matrix2D(maskWidth, maskHeight);

        // Time mask coefficient multiplication
        final coeffTimer = Stopwatch()..start();
        for (var y = scaledY1; y < scaledY2; y++) {
          if (y < 0 || y >= maskHeight) continue;
          for (var x = scaledX1; x < scaledX2; x++) {
            if (x < 0 || x >= maskWidth) continue;

            double maskValue = 0.0;
            for (var j = 0; j < 32; j++) {
              maskValue += maskCoeffs[j] * protoMasks[y][x][j];
            }
            mask160.set(x, y, maskValue);
          }
        }
        debugPrint(
            'Mask coefficient multiplication: ${coeffTimer.elapsedMilliseconds}ms');
        coeffTimer.stop();

        // Time sigmoid application
        final sigmoidTimer = Stopwatch()..start();
        mask160.applyRegion(scaledX1, scaledY1, scaledX2, scaledY2,
            (value) => 1 / (1 + math.exp(-value)));
        debugPrint(
            'Sigmoid application: ${sigmoidTimer.elapsedMilliseconds}ms');
        sigmoidTimer.stop();

        // Time thresholding
        final thresholdTimer = Stopwatch()..start();
        mask160.applyRegion(scaledX1, scaledY1, scaledX2, scaledY2,
            (value) => value > 0.5 ? 1.0 : 0.0);
        debugPrint('Thresholding: ${thresholdTimer.elapsedMilliseconds}ms');
        thresholdTimer.stop();

        // Time mask to image conversion
        final imageTimer = Stopwatch()..start();

        // Convert mask to image with default white color
        final maskImage = maskToImage(mask160);

        // Resize mask image to original image size
        final resizedMaskImage = img.copyResize(maskImage,
            width: originalWidth, height: originalHeight);

        // Example of how to create a colored mask:
        // final greenMask = maskToImage(
        //   mask160,
        //   color: Colors.green,
        //   opacity: 0.7,
        // );

        // Example of how to change color of existing mask:
        // final blackMask = changeImageColor(
        //   maskImage,
        //   newColor: Colors.black,
        //   opacity: 0.8,
        // );

        debugPrint(
            'Mask to image conversion: ${imageTimer.elapsedMilliseconds}ms');
        imageTimer.stop();

        detections.add(Detection(
          className: _labels![classIndex],
          confidence: confidence,
          rect: Rect.fromLTWH(
            x1,
            y1,
            x2 - x1,
            y2 - y1,
          ),
          maskImage: resizedMaskImage,
          id: detectionId++,
          color: _getColorForClass(_labels![classIndex]),
        ));
      }
    }
    debugPrint(
        'Total mask processing time: ${stopwatch.elapsedMilliseconds}ms');
    stopwatch.stop();
    return detections;
  }

  Color _getColorForClass(String className) {
    switch (className) {
      case 'license_plate':
        return const Color(0xFFFF0000); // Red
      case 'id_card':
        return const Color(0xFF0000FF); // Blue
      case 'screen':
        return const Color(0xFF00FF00); // Green
      default:
        return const Color(0xFFFFFF00); // Yellow
    }
  }

  /// Applies detection masks directly to the image with solid colors
//   img.Image applyMasksToImage(
//       img.Image originalImage, List<Detection> detections) {
//     final stopwatch = Stopwatch()..start();
//     debugPrint('Starting mask application...');

//     // Create a copy of the original image
//     final copyTimer = Stopwatch()..start();
//     final processedImage = img.copyResize(originalImage,
//         width: originalImage.width, height: originalImage.height);
//     debugPrint('Image copied in ${copyTimer.elapsedMilliseconds}ms');
//     copyTimer.stop();

//     // Apply each detection mask
//     for (final detection in detections) {
//       if (detection.mask == null) continue;

//       final maskTimer = Stopwatch()..start();
//       debugPrint('Processing mask for ${detection.className}...');

//       // Get mask dimensions
//       final int imageHeight = originalImage.height;
//       final int imageWidth = originalImage.width;

//       // Get color for this detection
//       final Color maskColor = _getColorForClass(detection.className);

//       // Apply the solid color where mask is active
//       for (var y = 0; y < imageHeight; y++) {
//         for (var x = 0; x < imageWidth; x++) {
//           if (y < detection.mask!.length &&
//               x < detection.mask![y].length &&
//               detection.mask![y][x] > 0.5) {
//             final originalPixel = processedImage.getPixel(x, y);
//             final r = ((originalPixel.r * 0.5) + (maskColor.red * 0.5)).toInt();
//             final g =
//                 ((originalPixel.g * 0.5) + (maskColor.green * 0.5)).toInt();
//             final b =
//                 ((originalPixel.b * 0.5) + (maskColor.blue * 0.5)).toInt();
//             processedImage.setPixelRgba(x, y, r, g, b, 255);
//           }
//         }
//       }
//       debugPrint(
//           'Mask for ${detection.className} applied in ${maskTimer.elapsedMilliseconds}ms');
//       maskTimer.stop();
//     }

//     debugPrint(
//         'Total mask application time: ${stopwatch.elapsedMilliseconds}ms');
//     stopwatch.stop();

//     return processedImage;
//   }
}

class Detection {
  // Detection information at 160x160 resolution
  final String className;
  final double confidence;
  final Rect rect;
  // final List<List<double>>? mask;
  final int id;
  final img.Image? maskImage;
  final Color? color;

  Detection({
    required this.className,
    required this.confidence,
    required this.rect,
    // this.mask,
    required this.id,
    this.maskImage,
    this.color,
  });
}
