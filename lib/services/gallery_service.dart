import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// A service class that handles gallery image picking operations.
/// This class manages gallery permissions and provides methods for selecting images.
class GalleryService {
  final ImagePicker _picker = ImagePicker();

  /// Checks if we already have the necessary permissions
  Future<bool> checkPermissions() async {
    // Check storage permission
    final storageStatus = await Permission.storage.status;
    if (!storageStatus.isGranted) {
      return false;
    }

    // On Android 13+, check photos permission
    final photosStatus = await Permission.photos.status;
    if (!photosStatus.isGranted) {
      return false;
    }

    return true;
  }

  /// Requests necessary permissions for accessing the gallery
  Future<bool> requestPermissions() async {
    // First check if we already have permissions
    if (await checkPermissions()) {
      return true;
    }

    // Request storage permission
    final storageStatus = await Permission.storage.request();
    if (storageStatus.isDenied) {
      return false;
    }

    // On Android 13+, request photos permission
    final photosStatus = await Permission.photos.request();
    if (photosStatus.isDenied) {
      return false;
    }

    return true;
  }

  /// Picks an image from the gallery
  /// Returns the selected image file or null if no image was selected
  Future<XFile?> pickImage() async {
    try {
      // First try to pick the image
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
      );

      // If image picker returns null, it might be due to permissions
      if (image == null) {
        // Check if we have permissions
        final hasPermission = await checkPermissions();
        if (!hasPermission) {
          // Request permissions
          final granted = await requestPermissions();
          if (!granted) {
            throw Exception(
              'Gallery permission denied. Please grant permission in settings.',
            );
          }
          // Try picking again after getting permissions
          return await _picker.pickImage(
            source: ImageSource.gallery,
          );
        }
      }

      return image;
    } catch (e) {
      throw Exception('Failed to pick image: $e');
    }
  }
}
