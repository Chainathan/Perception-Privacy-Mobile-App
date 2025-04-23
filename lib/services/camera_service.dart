import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

/// A service class that handles all camera-related operations.
/// This class manages the camera controller, permissions, and provides methods
/// for taking pictures.
class CameraService {
  // The camera controller that manages the camera hardware
  CameraController? _controller;
  // List of available cameras on the device
  List<CameraDescription>? _cameras;
  // Flag to track if the camera has been initialized
  bool _isInitialized = false;
  // Current camera index (0 for back, 1 for front)
  int _currentCameraIndex = 0;
  // Current flash mode
  FlashMode _currentFlashMode = FlashMode.off;

  /// Initializes the camera by:
  /// 1. Requesting camera permissions
  /// 2. Getting available cameras
  /// 3. Setting up the camera controller with the first available camera
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Request camera permission from the user
    final status = await Permission.camera.request();
    if (status.isDenied) {
      throw Exception('Camera permission denied');
    }

    // Get list of available cameras on the device
    _cameras = await availableCameras();
    if (_cameras!.isEmpty) {
      throw Exception('No cameras found');
    }

    // Initialize the first camera with medium resolution
    // ResolutionPreset.medium provides a good balance between quality and performance
    _controller = CameraController(
      _cameras![_currentCameraIndex],
      ResolutionPreset.medium,
      enableAudio: false, // We don't need audio for this app
    );

    try {
      await _controller!.initialize();
      // Set initial flash mode
      await _controller!.setFlashMode(_currentFlashMode);
      _isInitialized = true;
    } catch (e) {
      throw Exception('Failed to initialize camera: $e');
    }
  }

  // Getters to access private fields
  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  bool get hasMultipleCameras => _cameras != null && _cameras!.length > 1;
  FlashMode get currentFlashMode => _currentFlashMode;

  /// Properly disposes of the camera resources when they're no longer needed
  Future<void> dispose() async {
    try {
      if (_controller != null) {
        await _controller!.dispose();
        _controller = null;
      }
      _isInitialized = false;
      _cameras = null;
    } catch (e) {
      debugPrint('Error disposing camera: $e');
      // Even if there's an error, try to clean up as much as possible
      _controller = null;
      _isInitialized = false;
      _cameras = null;
    }
  }

  /// Takes a picture using the current camera
  /// Returns an XFile containing the captured image, or null if capture fails
  Future<XFile?> takePicture() async {
    if (!_isInitialized) {
      throw Exception('Camera not initialized');
    }

    try {
      // Set the flash mode for the picture
      await _controller!.setFlashMode(_currentFlashMode);
      final XFile image = await _controller!.takePicture();
      // Reset flash mode after taking picture
      await _controller!.setFlashMode(FlashMode.off);
      return image;
    } catch (e) {
      throw Exception('Failed to take picture: $e');
    }
  }

  /// Switches between front and back cameras
  Future<void> switchCamera() async {
    if (!_isInitialized || _cameras == null || _cameras!.length < 2) {
      return;
    }

    // Store current flash mode
    final currentFlash = _currentFlashMode;

    // Dispose of the current controller
    await _controller?.dispose();

    // Switch camera index
    _currentCameraIndex = (_currentCameraIndex + 1) % _cameras!.length;

    // Initialize new camera
    _controller = CameraController(
      _cameras![_currentCameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      // Restore flash mode after switching cameras
      await _controller!.setFlashMode(currentFlash);
    } catch (e) {
      throw Exception('Failed to switch camera: $e');
    }
  }

  /// Toggles the flash mode between on and off
  Future<void> toggleFlash() async {
    if (!_isInitialized) return;

    // Simply toggle between on and off
    FlashMode newMode =
        _currentFlashMode == FlashMode.off ? FlashMode.always : FlashMode.off;

    try {
      await _controller!.setFlashMode(newMode);
      _currentFlashMode = newMode;
    } catch (e) {
      debugPrint('Failed to set flash mode: $e');
      // If setting flash mode fails, try to reset to off
      try {
        await _controller!.setFlashMode(FlashMode.off);
        _currentFlashMode = FlashMode.off;
      } catch (e) {
        debugPrint('Failed to reset flash mode: $e');
      }
    }
  }
}
