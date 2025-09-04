import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:math' as math;

class TextRecognitionHelper {
  final TextRecognizer _textRecognizer;

  // Enhanced month pattern with all variants
  static final String _monthPattern =
      r'(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|'
      r'january|february|march|april|may|june|july|august|september|october|november|december|'
      r'01|02|03|04|05|06|07|08|09|10|11|12|'
      r'1|2|3|4|5|6|7|8|9|i|j|'
      r'JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)';

  // Regular expressions for identifying brand names and expiration dates
  static final RegExp _expiryDatePattern = RegExp(
    r'(exp\.?|expiry|exp date|expiration|valid until|best before|use by)[\s\.:-]*'
            r'(\d{1,2}[\/\.-]\d{1,2}[\/\.-]\d{2,4}|\d{1,2}[\s\.:-]?' +
        _monthPattern +
        r'[\.:\s-]*\d{2,4})',
    caseSensitive: false,
  );

  // Additional pattern for expiration dates without prefixes
  static final RegExp _simpleDatePattern = RegExp(
    r'(\d{1,2}[\/\.-]\d{1,2}[\/\.-]\d{2,4})',
    caseSensitive: true,
  );

  // Pattern for common date formats like MM/YYYY or MM-YYYY
  static final RegExp _monthYearPattern = RegExp(
    r'(\d{1,2}[\/\.-]\d{4})',
    caseSensitive: true,
  );

  // Pattern for month-year format with text months
  static final RegExp _textMonthYearPattern = RegExp(
    _monthPattern + r'[\.:\s-]*\d{2,4}',
    caseSensitive: false,
  );

  // Additional pattern for expiration dates with just EXP followed by numbers
  static final RegExp _expNumberPattern = RegExp(
    r'(?:EXP|EXPIRY|EXPIRES?)[\s\.:-]*(\d{1,2}[\s\/\.-]*\d{2,4})',
    caseSensitive: false,
  );

  TextRecognitionHelper() : _textRecognizer = TextRecognizer();

  Future<void> dispose() async {
    await _textRecognizer.close();
  }

  /// Process a CameraImage for text recognition
  Future<RecognitionResult> processImageForText(CameraImage cameraImage) async {
    try {
      // Convert CameraImage to format suitable for ML Kit
      final inputImage = await _convertCameraImageToInputImage(cameraImage);
      if (inputImage == null) {
        return RecognitionResult(
          success: false,
          errorMessage: 'Failed to convert image',
        );
      }

      // Process the image with ML Kit text recognizer
      final recognizedText = await _textRecognizer.processImage(inputImage);

      // Extract brand name and expiration date from recognized text
      final brandName = _extractBrandName(recognizedText.text);
      final expiryDate = _extractExpiryDate(recognizedText.text);

      if (kDebugMode) {
        print('Recognized text: ${recognizedText.text}');
        print('Extracted brand name: $brandName');
        print('Extracted expiry date: $expiryDate');

        // Print all lines to help debug expiration date extraction
        print('--- All recognized text lines ---');
        final lines = recognizedText.text.split('\n');
        for (int i = 0; i < lines.length; i++) {
          print('Line $i: ${lines[i]}');

          // Check each line for date patterns
          if (_expiryDatePattern.hasMatch(lines[i])) {
            print('  -> Contains expiry pattern');
            final match = _expiryDatePattern.firstMatch(lines[i]);
            if (match != null && match.groupCount >= 2) {
              print('  -> Extracted: ${match.group(2)}');
            }
          }
          if (_simpleDatePattern.hasMatch(lines[i])) {
            print('  -> Contains simple date pattern');
            final match = _simpleDatePattern.firstMatch(lines[i]);
            if (match != null) {
              print('  -> Extracted: ${match.group(0)}');
            }
          }
          if (_monthYearPattern.hasMatch(lines[i])) {
            print('  -> Contains month/year pattern');
            final match = _monthYearPattern.firstMatch(lines[i]);
            if (match != null) {
              print('  -> Extracted: ${match.group(0)}');
            }
          }
          if (_textMonthYearPattern.hasMatch(lines[i])) {
            print('  -> Contains text month/year pattern');
            final match = _textMonthYearPattern.firstMatch(lines[i]);
            if (match != null) {
              print('  -> Extracted: ${match.group(0)}');
            }
          }
        }
        print('-------------------------------');
      }

      return RecognitionResult(
        success: true,
        recognizedText: recognizedText.text,
        brandName: brandName,
        expiryDate: expiryDate,
      );
    } catch (e) {
      debugPrint('Error in text recognition: $e');
      return RecognitionResult(
        success: false,
        errorMessage: 'Error in text recognition: $e',
      );
    }
  }

  /// Convert CameraImage to InputImage for ML Kit
  Future<InputImage?> _convertCameraImageToInputImage(
    CameraImage cameraImage,
  ) async {
    try {
      // Create a temporary file to save the converted image
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_image.jpg');

      // Convert camera image to image format that can be saved
      img.Image? image = _convertCameraImageToImage(cameraImage);
      if (image == null) return null;

      // Encode as JPEG and save to file
      final jpegBytes = img.encodeJpg(image);
      await tempFile.writeAsBytes(jpegBytes);

      // Create InputImage from file
      return InputImage.fromFile(tempFile);
    } catch (e) {
      debugPrint('Error converting camera image: $e');
      return null;
    }
  }

  /// Convert CameraImage to image format
  img.Image? _convertCameraImageToImage(CameraImage cameraImage) {
    try {
      // Handle YUV_420_888 format (most common on Android)
      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        return _convertYUV420ToImage(cameraImage);
      }
      // Handle bgra8888 format (common on iOS)
      else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        return _convertBGRA8888ToImage(cameraImage);
      } else {
        debugPrint('Unsupported image format: ${cameraImage.format.group}');
        return null;
      }
    } catch (e) {
      debugPrint('Error in image conversion: $e');
      return null;
    }
  }

  /// Convert YUV_420_888 format to Image
  img.Image _convertYUV420ToImage(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;

    // Create image with correct dimensions
    final image = img.Image(width: width, height: height);

    // Convert YUV to RGB
    final yBuffer = cameraImage.planes[0].bytes;
    final uBuffer = cameraImage.planes[1].bytes;
    final vBuffer = cameraImage.planes[2].bytes;

    final yRowStride = cameraImage.planes[0].bytesPerRow;
    final uvRowStride = cameraImage.planes[1].bytesPerRow;
    final uvPixelStride = cameraImage.planes[1].bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final yIndex = y * yRowStride + x;
        final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

        final yValue = yBuffer[yIndex];
        final uValue = uBuffer[uvIndex];
        final vValue = vBuffer[uvIndex];

        // YUV to RGB conversion
        int r = (yValue + 1.402 * (vValue - 128)).round().clamp(0, 255);
        int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
            .round()
            .clamp(0, 255);
        int b = (yValue + 1.772 * (uValue - 128)).round().clamp(0, 255);

        image.setPixelRgb(x, y, r, g, b);
      }
    }

    return image;
  }

  /// Convert BGRA_8888 format to Image
  img.Image _convertBGRA8888ToImage(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;

    // Create image with correct dimensions
    final image = img.Image(width: width, height: height);

    // Get byte data from the image
    final bytes = cameraImage.planes[0].bytes;
    final bytesPerRow = cameraImage.planes[0].bytesPerRow;

    // BGRA to RGB conversion
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixelIndex = y * bytesPerRow + x * 4;
        final b = bytes[pixelIndex];
        final g = bytes[pixelIndex + 1];
        final r = bytes[pixelIndex + 2];

        image.setPixelRgb(x, y, r, g, b);
      }
    }

    return image;
  }

  /// Extract brand name from recognized text using heuristics
  String? _extractBrandName(String text) {
    if (text.isEmpty) return null;

    // Split text into lines
    final lines = text.split('\n');

    // Brand names are often at the top of the package and in larger font
    // They are typically short lines (1-3 words) with capitalized letters
    for (final line in lines) {
      final trimmedLine = line.trim();

      // Skip very short lines
      if (trimmedLine.length < 3) continue;

      // Skip lines that likely contain expiration dates
      if (_expiryDatePattern.hasMatch(trimmedLine)) continue;

      // Brand names are often all caps or have the first letter of each word capitalized
      if (trimmedLine == trimmedLine.toUpperCase() ||
          trimmedLine
              .split(' ')
              .every(
                (word) => word.length > 0 && word[0] == word[0].toUpperCase(),
              )) {
        // Additional checks to avoid common false positives
        if (!trimmedLine.contains('MG') &&
            !trimmedLine.contains('TABLET') &&
            !trimmedLine.contains('CAPSULE')) {
          // Limit to reasonable brand name length
          final words = trimmedLine.split(' ');
          if (words.length <= 3 && trimmedLine.length <= 25) {
            return trimmedLine;
          }
        }
      }
    }

    return null;
  }

  /// Extract expiration date from recognized text
  String? _extractExpiryDate(String text) {
    if (text.isEmpty) return null;

    // Convert text to uppercase for better matching
    final upperText = text.toUpperCase();

    // Look for common expiry indicators followed by dates
    for (final indicator in [
      'EXP',
      'EXPIRY',
      'EXPIRATION',
      'USE BY',
      'BEST BEFORE',
    ]) {
      if (upperText.contains(indicator)) {
        // Find the position of the indicator
        final pos = upperText.indexOf(indicator);
        // Extract the text after the indicator (limited to 20 chars to avoid grabbing too much)
        final afterText = upperText.substring(
          pos + indicator.length,
          math.min(pos + indicator.length + 20, upperText.length),
        );

        // Look for date patterns in this text
        final dateMatch = RegExp(
          r'\d{1,2}[\s\/\.-]+(?:\d{1,2}[\s\/\.-]+)?\d{2,4}',
        ).firstMatch(afterText);
        if (dateMatch != null) {
          return dateMatch.group(0);
        }

        // Look for text month patterns
        final monthMatch = RegExp(
          r'(?:JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[\s\.:-]*\d{2,4}',
          caseSensitive: false,
        ).firstMatch(afterText);
        if (monthMatch != null) {
          return monthMatch.group(0);
        }
      }
    }

    // Look for expiration date patterns with explicit labels
    final match = _expiryDatePattern.firstMatch(text);
    if (match != null && match.groupCount >= 2) {
      return match.group(2)?.trim();
    }

    // Look for simple EXP followed by numbers pattern
    final expNumberMatch = _expNumberPattern.firstMatch(text);
    if (expNumberMatch != null && expNumberMatch.groupCount >= 1) {
      return expNumberMatch.group(1)?.trim();
    }

    // Look for standalone date formats that might be expiration dates
    final lines = text.split('\n');
    for (final line in lines) {
      final trimmedLine = line.trim();

      // Skip very short lines
      if (trimmedLine.length < 3) continue;

      // Check for text month-year format (e.g., "JAN 2024", "JAN/2024", etc.)
      final textMonthYearMatch = _textMonthYearPattern.firstMatch(trimmedLine);
      if (textMonthYearMatch != null) {
        return textMonthYearMatch.group(0)?.trim();
      }

      // Check for month/year format (e.g., "01/2024", "1-2024", etc.)
      final monthYearMatch = _monthYearPattern.firstMatch(trimmedLine);
      if (monthYearMatch != null) {
        return monthYearMatch.group(0)?.trim();
      }

      // Check for full date format (e.g., "01/01/2024", "1.1.24", etc.)
      final dateMatch = _simpleDatePattern.firstMatch(trimmedLine);
      if (dateMatch != null) {
        final dateStr = dateMatch.group(0)?.trim();

        // Try to parse the date to check if it's in the future
        try {
          final parts = dateStr!.split(RegExp(r'[\/\.-]'));
          if (parts.length == 3) {
            int? year = int.tryParse(parts[2]);
            // If year is 2-digit format, adjust to 4-digit
            if (year != null && year < 100) {
              year += 2000; // Assume 20xx for 2-digit years
            }

            // Only return dates that are likely in the future
            if (year != null && year >= DateTime.now().year) {
              return dateStr;
            }
          }
        } catch (e) {
          // If parsing fails, still return the date as it might be valid
          return dateStr;
        }
      }
    }

    return null;
  }
}

/// Class to encapsulate text recognition results
class RecognitionResult {
  final bool success;
  final String? errorMessage;
  final String? recognizedText;
  final String? brandName;
  final String? expiryDate;

  RecognitionResult({
    required this.success,
    this.errorMessage,
    this.recognizedText,
    this.brandName,
    this.expiryDate,
  });
}
