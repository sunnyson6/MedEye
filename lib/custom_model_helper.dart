import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'model_config.dart';

/// A helper class to handle YOLOv8 model inference with different formats
class YoloModelHelper {
  final Interpreter interpreter;
  List<int>? _inputShape;
  List<int>? _outputShape;
  bool _isInitialized = false;

  /// Factory method to safely create a YoloModelHelper, with better error handling
  static Future<YoloModelHelper?> create({
    required Interpreter interpreter,
  }) async {
    try {
      final helper = YoloModelHelper._internal(interpreter: interpreter);
      await helper._initialize();
      return helper;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to create YoloModelHelper: $e');
      }
      return null;
    }
  }

  // Private constructor to prevent direct instantiation
  YoloModelHelper._internal({required this.interpreter});

  // For backward compatibility
  YoloModelHelper({required this.interpreter}) {
    // Call _initialize but don't wait for it, for backward compatibility
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _inputShape = interpreter.getInputTensor(0).shape;
      _outputShape = interpreter.getOutputTensor(0).shape;

      // For float32 models, explicitly allocate tensors
      interpreter.allocateTensors();

      _isInitialized = true;

      if (kDebugMode) {
        print('YoloModelHelper initialized with:');
        print('Input shape: $_inputShape');
        print('Output shape: $_outputShape');
        print('Input tensor type: ${interpreter.getInputTensor(0).type}');
        print('Output tensor type: ${interpreter.getOutputTensor(0).type}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing YoloModelHelper: $e');
        print('Error details: ${e.toString()}');
      }
      _isInitialized = false;
      // Rethrow to allow factory method to catch
      rethrow;
    }
  }

  /// Run inference on the model with proper input/output formatting
  Future<List<double>> runInference(List<double> inputData) async {
    if (!_isInitialized) {
      if (kDebugMode) {
        print(
          'Warning: YoloModelHelper not initialized, trying to initialize now',
        );
      }
      try {
        await _initialize();
      } catch (e) {
        if (kDebugMode) {
          print('Failed to initialize on demand: $e');
        }
        return [];
      }
    }

    try {
      // Get input and output tensors
      final inputTensor = interpreter.getInputTensor(0);
      final outputTensor = interpreter.getOutputTensor(0);
      final outputSize = outputTensor.shape.reduce((a, b) => a * b);

      if (kDebugMode) {
        print('Input tensor shape: ${inputTensor.shape}');
        print('Output tensor shape: ${outputTensor.shape}');
        print('Input tensor type: ${inputTensor.type}');
        print('Output tensor type: ${outputTensor.type}');
      }

      // For float32 models, we can optimize by using compute for better UI responsiveness
      if (USE_ISOLATE) {
        // Run in compute isolate for better performance
        final result = await compute(_runInferenceIsolate, {
          'interpreter': interpreter,
          'inputData': inputData,
        });
        return result;
      }

      // Direct buffer approach for float32
      final inputFloat32 = Float32List.fromList(inputData);
      final outputFloat32 = Float32List(outputSize);

      // Run inference
      interpreter.run(
        inputFloat32.buffer.asUint8List(),
        outputFloat32.buffer.asUint8List(),
      );

      // Return the output as list of doubles
      return outputFloat32.toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error running inference: $e');
        print('Error details: ${e.toString()}');
      }
      return [];
    }
  }

  /// Run inference directly in the main thread as a fallback
  List<double> _runInferenceInMainThread(List<double> inputData) {
    if (kDebugMode) {
      print('Attempting inference in main thread');
    }

    try {
      // Get output tensor
      final inputTensor = interpreter.getInputTensor(0);
      final outputTensor = interpreter.getOutputTensor(0);
      final outputSize = outputTensor.shape.reduce((a, b) => a * b);

      // Direct buffer approach for float32
      final inputFloat32 = Float32List.fromList(inputData);
      final outputFloat32 = Float32List(outputSize);

      // Run inference
      interpreter.run(
        inputFloat32.buffer.asUint8List(),
        outputFloat32.buffer.asUint8List(),
      );

      // Return the output as list of doubles
      return outputFloat32.toList();
    } catch (e) {
      if (kDebugMode) {
        print('Main thread inference failed: $e');
      }
      return [];
    }
  }

  /// Create output buffer based on shape
  List<List<List<List<double>>>> _createOutputBuffer(List<int> shape) {
    if (shape.length == 4) {
      // Handle 4D shape
      return List<List<List<List<double>>>>.filled(
        shape[0],
        List<List<List<double>>>.filled(
          shape[1],
          List<List<double>>.filled(
            shape[2],
            List<double>.filled(shape[3], 0.0),
          ),
        ),
      );
    } else if (shape.length == 3) {
      // Handle 3D shape - wrap it in a 4D structure for compatibility
      // This works around the error "Expected 4D output shape, got 3D"
      return [
        List<List<List<double>>>.filled(
          shape[0],
          List<List<double>>.filled(
            shape[1],
            List<double>.filled(shape[2], 0.0),
          ),
        ),
      ];
    } else {
      throw Exception('Expected 4D or 3D output shape, got ${shape.length}D');
    }
  }

  /// Flatten output to 1D list
  List<double> _flattenOutput(
    List<List<List<List<double>>>> output,
    List<int> shape,
  ) {
    final outputData = <double>[];

    // Flatten based on the shape
    for (int i = 0; i < shape[0]; i++) {
      for (int j = 0; j < shape[1]; j++) {
        for (int k = 0; k < shape[2]; k++) {
          for (int l = 0; l < shape[3]; l++) {
            outputData.add(output[i][j][k][l]);
          }
        }
      }
    }

    return outputData;
  }

  // Flatten 3D output to 1D list - specifically for YOLO output
  List<double> _flatten3DOutput(List<List<List<double>>> output) {
    final outputData = <double>[];

    // Check output shape configuration - [1, 6, 8400] format
    final isTransposed = TRANSPOSE_OUTPUT;

    if (!isTransposed) {
      // Format is [1, 6, 8400] - rearrange to expected flat layout
      for (int i = 0; i < YOLO8_OUTPUTS; i++) {
        for (int j = 0; j < YOLO8_DIMENSIONS; j++) {
          outputData.add(output[0][j][i]);
        }
      }
    } else {
      // Format is [1, 8400, 6] - simple flatten
      for (int i = 0; i < output[0].length; i++) {
        for (int j = 0; j < output[0][i].length; j++) {
          outputData.add(output[0][i][j]);
        }
      }
    }

    return outputData;
  }
}

/// Implementation of inference in compute isolate
List<double> _runInferenceIsolate(Map<String, dynamic> params) {
  final Interpreter interpreter = params['interpreter'];
  final List<double> inputData = params['inputData'];

  if (kDebugMode) {
    print('Running inference in isolate');
  }

  try {
    // Get input and output tensors
    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    final outputSize = outputTensor.shape.reduce((a, b) => a * b);

    // For float32 model, we can use Float32List directly
    final inputFloat32 = Float32List.fromList(inputData);
    final outputFloat32 = Float32List(outputSize);

    // Use direct buffer for both input and output
    interpreter.run(
      inputFloat32.buffer.asUint8List(),
      outputFloat32.buffer.asUint8List(),
    );

    // Convert back to List<double>
    return outputFloat32.toList();
  } catch (e) {
    if (kDebugMode) {
      print('Error in inference isolate: $e');
      print('Error details: ${e.toString()}');
    }
    return [];
  }
}
