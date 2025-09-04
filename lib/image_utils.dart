import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'model_config.dart';
import 'dart:typed_data';

// Define a class to hold region of interest information
class RegionOfInterest {
  final int left;
  final int top;
  final int width;
  final int height;

  RegionOfInterest({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

// Process the camera image for YOLOv8 model
Future<List<double>> processImageForYolo(
  CameraImage image, [
  RegionOfInterest? roi,
]) async {
  // Using compute isolate to move processing off the main thread
  return await compute(_processYoloFrame, {'image': image, 'roi': roi});
}

List<double> _processYoloFrame(Map<String, dynamic> params) {
  final CameraImage image = params['image'];
  final RegionOfInterest? roi = params['roi'];

  // For float32 models, create the buffer directly
  final inputData = Float32List(INPUT_SIZE * INPUT_SIZE * CHANNELS);

  try {
    if (image.format.group == ImageFormatGroup.yuv420) {
      _processYUV420(image, roi, inputData);
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      _processBGRA8888(image, roi, inputData);
    } else {
      if (kDebugMode) {
        print("Unsupported image format: ${image.format.group}");
      }
    }
  } catch (e) {
    if (kDebugMode) {
      print("Error processing image: $e");
    }
  }

  // Convert from Float32List to List<double>
  return inputData.toList();
}

void _processYUV420(
  CameraImage image,
  RegionOfInterest? roi,
  Float32List inputData,
) {
  // Get original dimensions
  final int originalWidth = image.width;
  final int originalHeight = image.height;

  // If ROI is provided, use it, otherwise use the full image
  final int sourceLeft = roi?.left ?? 0;
  final int sourceTop = roi?.top ?? 0;
  final int sourceWidth = roi?.width ?? originalWidth;
  final int sourceHeight = roi?.height ?? originalHeight;

  if (kDebugMode) {
    print(
      "Processing ROI: ($sourceLeft, $sourceTop, $sourceWidth, $sourceHeight)",
    );
  }

  // Camera data
  final yBuffer = image.planes[0].bytes;
  final uBuffer = image.planes[1].bytes;
  final vBuffer = image.planes[2].bytes;

  final yRowStride = image.planes[0].bytesPerRow;
  final uvRowStride = image.planes[1].bytesPerRow;
  final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

  // Calculate letterboxing/padding to preserve aspect ratio
  // This is critical for accurate bounding box predictions
  double scale;
  int paddingLeft = 0;
  int paddingTop = 0;

  // Calculate how to scale the image while preserving aspect ratio
  if (sourceWidth / sourceHeight > 1) {
    // Width is the limiting factor
    scale = INPUT_SIZE / sourceWidth;
    paddingTop = ((INPUT_SIZE - (sourceHeight * scale).round()) / 2).round();
  } else {
    // Height is the limiting factor
    scale = INPUT_SIZE / sourceHeight;
    paddingLeft = ((INPUT_SIZE - (sourceWidth * scale).round()) / 2).round();
  }

  // Calculate target dimensions after scaling
  final targetWidth = (sourceWidth * scale).round();
  final targetHeight = (sourceHeight * scale).round();

  if (kDebugMode) {
    print(
      "Letterboxing: scale=$scale, padding left=$paddingLeft, top=$paddingTop",
    );
    print("Target dimensions: $targetWidth x $targetHeight");
  }

  // Fill the entire input with zeros (black pixels)
  for (int i = 0; i < inputData.length; i++) {
    inputData[i] = 0.0;
  }

  // Process only the parts of the input tensor that will contain the image
  for (int y = 0; y < targetHeight; y++) {
    for (int x = 0; x < targetWidth; x++) {
      // Calculate source pixel in the ROI
      final srcX = sourceLeft + ((x / scale).floor());
      final srcY = sourceTop + ((y / scale).floor());

      // Skip if out of bounds
      if (srcX < 0 ||
          srcX >= originalWidth ||
          srcY < 0 ||
          srcY >= originalHeight) {
        continue;
      }

      final int yIndex = srcY * yRowStride + srcX;
      final int uvIndex =
          (srcY ~/ 2) * uvRowStride + (srcX ~/ 2) * uvPixelStride;

      // Check bounds for safe access
      if (yIndex < yBuffer.length &&
          uvIndex < uBuffer.length &&
          uvIndex < vBuffer.length) {
        // Get YUV components
        final yChannel = yBuffer[yIndex] & 0xFF; // Ensure unsigned byte
        final uChannel = uBuffer[uvIndex] & 0xFF;
        final vChannel = vBuffer[uvIndex] & 0xFF;

        // Improved YUV to RGB conversion formula
        // BT.601 standard for YUV to RGB conversion
        int r = (yChannel + 1.402 * (vChannel - 128)).round().clamp(0, 255);
        int g = (yChannel -
                0.344136 * (uChannel - 128) -
                0.714136 * (vChannel - 128))
            .round()
            .clamp(0, 255);
        int b = (yChannel + 1.772 * (uChannel - 128)).round().clamp(0, 255);

        // Calculate position in the target (letter-boxed) image
        final targetX = paddingLeft + x;
        final targetY = paddingTop + y;

        // Skip if out of bounds of the target area
        if (targetX < 0 ||
            targetX >= INPUT_SIZE ||
            targetY < 0 ||
            targetY >= INPUT_SIZE) {
          continue;
        }

        // YOLOv8 expects RGB format normalized to 0-1 range
        final int tensorIndex = (targetY * INPUT_SIZE + targetX) * CHANNELS;
        inputData[tensorIndex] = r / 255.0;
        inputData[tensorIndex + 1] = g / 255.0;
        inputData[tensorIndex + 2] = b / 255.0;
      }
    }
  }
}

void _processBGRA8888(
  CameraImage image,
  RegionOfInterest? roi,
  Float32List inputData,
) {
  // Get original dimensions
  final int originalWidth = image.width;
  final int originalHeight = image.height;

  // If ROI is provided, use it, otherwise use the full image
  final int sourceLeft = roi?.left ?? 0;
  final int sourceTop = roi?.top ?? 0;
  final int sourceWidth = roi?.width ?? originalWidth;
  final int sourceHeight = roi?.height ?? originalHeight;

  // Camera data
  final bgra = image.planes[0].bytes;
  final rowStride = image.planes[0].bytesPerRow;
  final pixelStride = image.planes[0].bytesPerPixel ?? 4;

  // Calculate letterboxing/padding to preserve aspect ratio
  double scale;
  int paddingLeft = 0;
  int paddingTop = 0;

  // Calculate how to scale the image while preserving aspect ratio
  if (sourceWidth / sourceHeight > 1) {
    // Width is the limiting factor
    scale = INPUT_SIZE / sourceWidth;
    paddingTop = ((INPUT_SIZE - (sourceHeight * scale).round()) / 2).round();
  } else {
    // Height is the limiting factor
    scale = INPUT_SIZE / sourceHeight;
    paddingLeft = ((INPUT_SIZE - (sourceWidth * scale).round()) / 2).round();
  }

  // Calculate target dimensions after scaling
  final targetWidth = (sourceWidth * scale).round();
  final targetHeight = (sourceHeight * scale).round();

  // Fill the entire input with zeros (black pixels)
  for (int i = 0; i < inputData.length; i++) {
    inputData[i] = 0.0;
  }

  // Process only the parts of the input tensor that will contain the image
  for (int y = 0; y < targetHeight; y++) {
    for (int x = 0; x < targetWidth; x++) {
      // Calculate source pixel in the ROI
      final srcX = sourceLeft + ((x / scale).floor());
      final srcY = sourceTop + ((y / scale).floor());

      // Skip if out of bounds
      if (srcX < 0 ||
          srcX >= originalWidth ||
          srcY < 0 ||
          srcY >= originalHeight) {
        continue;
      }

      final int pixelIndex = srcY * rowStride + srcX * pixelStride;

      // Check bounds for safe access
      if (pixelIndex + 2 < bgra.length) {
        // BGRA format coming from the camera
        final b = bgra[pixelIndex] & 0xFF;
        final g = bgra[pixelIndex + 1] & 0xFF;
        final r = bgra[pixelIndex + 2] & 0xFF;

        // Calculate position in the target (letter-boxed) image
        final targetX = paddingLeft + x;
        final targetY = paddingTop + y;

        // Skip if out of bounds of the target area
        if (targetX < 0 ||
            targetX >= INPUT_SIZE ||
            targetY < 0 ||
            targetY >= INPUT_SIZE) {
          continue;
        }

        // Convert to RGB for YOLOv8 in NHWC layout, normalized to 0-1
        final int tensorIndex = (targetY * INPUT_SIZE + targetX) * CHANNELS;
        inputData[tensorIndex] = r / 255.0;
        inputData[tensorIndex + 1] = g / 255.0;
        inputData[tensorIndex + 2] = b / 255.0;
      }
    }
  }
}

// Helper function to reshape the flat tensor for visualization
List<List<List<double>>> reshapeFlatTensorToImage(
  List<double> flatTensor,
  int width,
  int height,
  int channels,
) {
  final result = List.generate(
    height,
    (y) => List.generate(
      width,
      (x) => List.generate(channels, (c) {
        final index = (y * width + x) * channels + c;
        return flatTensor[index];
      }),
    ),
  );

  return result;
}
