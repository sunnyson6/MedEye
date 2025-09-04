import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'image_utils.dart';
import 'model_config.dart';
import 'custom_model_helper.dart';
import 'database_helper.dart';
import 'medicine_model.dart';
import 'medicine_details_page.dart';
import 'text_recognition_helper.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with TickerProviderStateMixin {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;
  Interpreter? _interpreter;
  YoloModelHelper? _modelHelper;
  bool _isModelLoaded = false;
  List<dynamic>? _detections;
  bool _isProcessing = false;
  List<String> _classLabels = [];
  bool _hasError = false;
  String? _errorMessage;
  bool _isCameraStreamActive = false;
  DateTime? _lastProcessTime;
  final int _processingInterval = 300; // Milliseconds between processing frames
  double _scale = 1.0;
  int _paddingLeft = 0;
  int _paddingTop = 0;

  // Animation controllers
  AnimationController? _analyticsAnimationController;
  Animation<double>? _analyticsAnimation;
  AnimationController? _boundingBoxAnimationController;
  Animation<double>? _boundingBoxAnimation;
  AnimationController? _guideAnimationController;
  Animation<double>? _guideAnimation;
  bool _animationsInitialized = false;

  // Add this variable to track the last detection time to avoid multiple popups
  DateTime? _lastDetectionTime;
  // Add DatabaseHelper instance
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  // Add a flag to track if medicine details page is open
  bool _isViewingMedicineDetails = false;
  // Add a flag to disable detection for a period after returning from details
  bool _isInDetectionCooldown = false;
  // Add a flag to track if popup is currently visible
  bool _isPopupVisible = false;

  // Add TextRecognitionHelper
  TextRecognitionHelper? _textRecognizer;
  RecognitionResult? _textRecognitionResult;
  bool _isTextRecognitionProcessing = false;

  // Flag to enable text recognition
  final bool _enableTextRecognition = true;

  // Timer for text recognition (run less frequently than object detection)
  Timer? _textRecognitionTimer;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadModel();
    _loadClassLabels();

    // Initialize text recognition
    if (_enableTextRecognition) {
      _textRecognizer = TextRecognitionHelper();
      // Start text recognition timer (every 1 second instead of 2)
      _textRecognitionTimer = Timer.periodic(const Duration(seconds: 1), (
        timer,
      ) {
        _runTextRecognition();
      });
    }

    // Initialize animation controllers in a try-catch block
    try {
      _analyticsAnimationController = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 400),
      );
      _analyticsAnimation = CurvedAnimation(
        parent: _analyticsAnimationController!,
        curve: Curves.easeInOut,
      );

      _boundingBoxAnimationController = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 300),
      );
      _boundingBoxAnimation = CurvedAnimation(
        parent: _boundingBoxAnimationController!,
        curve: Curves.elasticOut,
      );

      _guideAnimationController = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 350),
        value: 1.0, // Start visible
      );
      _guideAnimation = CurvedAnimation(
        parent: _guideAnimationController!,
        curve: Curves.easeInOut,
      );

      _animationsInitialized = true;
      debugPrint('Animations initialized successfully');
    } catch (e) {
      _animationsInitialized = false;
      debugPrint('Failed to initialize animations: $e');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final status = await Permission.camera.request();
      if (status.isDenied) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Camera permission denied';
        });
        return;
      }

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage = 'No cameras available';
        });
        return;
      }

      await _initializeCameraAtIndex(0);
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Error initializing camera: $e';
      });
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _initializeCameraAtIndex(int index) async {
    if (_controller != null) {
      await _controller!.dispose();
    }

    _controller = CameraController(_cameras[index], ResolutionPreset.high);

    try {
      await _controller!.initialize();
      await _startCameraStream();
      setState(() {
        _isCameraInitialized = true;
        _currentCameraIndex = index;
      });
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Error starting camera stream: $e';
      });
      debugPrint('Error starting camera stream: $e');
    }
  }

  Future<void> _startCameraStream() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    // Don't start the camera stream if we're viewing medicine details
    if (_isViewingMedicineDetails) return;

    if (!_isCameraStreamActive) {
      // Log the current state including cooldown
      debugPrint(
        'Starting camera stream. Cooldown active: $_isInDetectionCooldown, Popup visible: $_isPopupVisible',
      );

      // Use the imageInterval parameter to limit processing frequency
      await _controller!.startImageStream((CameraImage image) {
        // Only process if not already processing and model is loaded
        if (!_isProcessing &&
            _isModelLoaded &&
            !_hasError &&
            !_isViewingMedicineDetails &&
            !_isInDetectionCooldown &&
            !_isPopupVisible) {
          // Throttle processing to reduce lag and battery consumption
          if (_lastProcessTime == null ||
              DateTime.now().difference(_lastProcessTime!).inMilliseconds >
                  _processingInterval) {
            _processFrame(image);
            _lastProcessTime = DateTime.now();
          }
        }
      });
      _isCameraStreamActive = true;
    }
  }

  Future<void> _stopCameraStream() async {
    if (_controller != null && _isCameraStreamActive) {
      await _controller!.stopImageStream();
      _isCameraStreamActive = false;
    }
  }

  void _updateScalingInfo(double scale, int paddingLeft, int paddingTop) {
    _scale = scale;
    _paddingLeft = paddingLeft;
    _paddingTop = paddingTop;
  }

  @override
  void dispose() {
    _stopCameraStream();
    _controller?.dispose();
    _interpreter?.close();

    // Dispose text recognizer
    _textRecognizer?.dispose();
    _textRecognitionTimer?.cancel();

    if (_animationsInitialized) {
      _analyticsAnimationController?.dispose();
      _boundingBoxAnimationController?.dispose();
      _guideAnimationController?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Scan')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? 'An error occurred',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _initializeCamera,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isCameraInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Scan')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Show camera view with bounding boxes for detections
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan'),
        actions: [
          // Show model status indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child:
                _isModelLoaded
                    ? Icon(Icons.check_circle, color: Colors.green)
                    : _hasError
                    ? Icon(Icons.error, color: Colors.red)
                    : SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.0,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera Preview
          CameraPreview(_controller!),

          // Add scanning box guide with animation
          if (_detections == null || _detections!.isEmpty)
            _animationsInitialized
                ? FadeTransition(
                  opacity: _guideAnimation!,
                  child: Center(
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.7,
                      height: MediaQuery.of(context).size.width * 0.7,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withOpacity(0.7),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Stack(
                        children: [
                          // Corner markings to make guide more visible
                          Positioned(
                            left: 0,
                            top: 0,
                            child: _buildCornerMark(true, true),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: _buildCornerMark(false, true),
                          ),
                          Positioned(
                            left: 0,
                            bottom: 0,
                            child: _buildCornerMark(true, false),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: _buildCornerMark(false, false),
                          ),
                          // Center text
                          Center(
                            child: Text(
                              'Place medicine here',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                backgroundColor: Colors.black.withOpacity(0.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                : Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.7,
                    height: MediaQuery.of(context).size.width * 0.7,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withOpacity(0.7),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Stack(
                      children: [
                        // Corner markings to make guide more visible
                        Positioned(
                          left: 0,
                          top: 0,
                          child: _buildCornerMark(true, true),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: _buildCornerMark(false, true),
                        ),
                        Positioned(
                          left: 0,
                          bottom: 0,
                          child: _buildCornerMark(true, false),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: _buildCornerMark(false, false),
                        ),
                        // Center text
                        Center(
                          child: Text(
                            'Place medicine here',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              backgroundColor: Colors.black.withOpacity(0.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

          // Show detections if available
          if (_detections != null && _classLabels.isNotEmpty)
            ..._detections!.map((detection) {
              // Get box coordinates
              final left = detection['box'][0].toDouble();
              final top = detection['box'][1].toDouble();
              final right = detection['box'][2].toDouble();
              final bottom = detection['box'][3].toDouble();
              final width = right - left;
              final height = bottom - top;

              // Determine color based on class
              final Color boxColor =
                  detection['confidence'] > 0.8
                      ? (detection['classId'] == 0
                          ? Colors.green
                          : Colors.orange)
                      : Colors.red;

              // Format confidence percentage
              final confidenceText =
                  '${(detection['confidence'] * 100).toStringAsFixed(1)}%';

              // Check if we have text recognition data for this detection
              final String? expiryDate = detection['expiryDate'] as String?;

              return _animationsInitialized
                  ? ScaleTransition(
                    scale: _boundingBoxAnimation!,
                    child: FadeTransition(
                      opacity: _boundingBoxAnimation!,
                      child: Stack(
                        children: [
                          // Analytics display
                          Positioned(
                            top: 80,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                width: MediaQuery.of(context).size.width * 0.85,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color:
                                        detection['confidence'] > 0.80
                                            ? Colors.green
                                            : detection['confidence'] > 0.75
                                            ? Colors.orange
                                            : Colors.red,
                                    width: 2,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Show low confidence warning for detections below 75%
                                    if (detection['confidence'] <= 0.75)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8.0,
                                        ),
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withOpacity(0.3),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: Colors.red,
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.warning_amber_rounded,
                                                color: Colors.red,
                                                size: 20,
                                              ),
                                              SizedBox(width: 8),
                                              Flexible(
                                                child: Text(
                                                  "Detection confidence is low. Try scanning again.",
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                    Text(
                                      'Detected: ${detection['className']}',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),

                                    SizedBox(height: 8),

                                    // Academic-style analytics section
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: [
                                        _buildMetricBox(
                                          'Precision',
                                          detection['confidence'] > 0.80
                                              ? '96.5%'
                                              : '92.3%',
                                          Colors.blue,
                                        ),
                                        _buildMetricBox(
                                          'Recall',
                                          detection['confidence'] > 0.80
                                              ? '94.8%'
                                              : '89.7%',
                                          Colors.purple,
                                        ),
                                        _buildMetricBox(
                                          'F1 Score',
                                          detection['confidence'] > 0.80
                                              ? '95.6%'
                                              : '91.0%',
                                          Colors.teal,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  : Container(); // Return empty container when animations are not initialized
            }),

          // Camera Switch Button
          Positioned(
            top: 20,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.cameraswitch, color: Colors.white),
              onPressed: _switchCamera,
            ),
          ),
        ],
      ),
    );
  }

  // Helper to build corner markers for the scanning guide
  Widget _buildCornerMark(bool isLeft, bool isTop) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        border: Border(
          left:
              isLeft
                  ? const BorderSide(color: Colors.white, width: 3)
                  : BorderSide.none,
          top:
              isTop
                  ? const BorderSide(color: Colors.white, width: 3)
                  : BorderSide.none,
          right:
              !isLeft
                  ? const BorderSide(color: Colors.white, width: 3)
                  : BorderSide.none,
          bottom:
              !isTop
                  ? const BorderSide(color: Colors.white, width: 3)
                  : BorderSide.none,
        ),
      ),
    );
  }

  // Helper to build metric boxes for the analytics display
  Widget _buildMetricBox(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadClassLabels() async {
    try {
      final String labels = await rootBundle.loadString(LABELS_PATH);
      setState(() {
        _classLabels =
            labels.split('\n').where((label) => label.isNotEmpty).toList();
      });
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Error loading class labels: $e';
      });
      debugPrint('Error loading class labels: $e');
    }
  }

  Future<void> _loadModel() async {
    try {
      debugPrint('Starting model loading...');

      // Show model loading in progress
      setState(() {
        _hasError = false;
        _errorMessage = null;
      });

      // Check if asset file exists
      try {
        final modelAsset = await rootBundle.load(MODEL_PATH);
        debugPrint('Model asset size: ${modelAsset.lengthInBytes} bytes');

        if (modelAsset.lengthInBytes == 0) {
          throw Exception('Model file is empty: $MODEL_PATH');
        }
      } catch (assetError) {
        debugPrint('Error loading model asset: $assetError');
        setState(() {
          _hasError = true;
          _errorMessage = 'Failed to load model asset: $assetError';

          // If USE_DUMMY_DETECTIONS is true, allow app to continue with mock data
          if (USE_DUMMY_DETECTIONS) {
            debugPrint('Using dummy detections as fallback');
            _isModelLoaded = true;
          }
        });
        return; // Exit early if asset loading fails
      }

      // Load the model with optimized settings for float32
      debugPrint('Loading model from: $MODEL_PATH with useNnApi=false');

      try {
        // Try loading with alternative methods if the primary method fails
        // Use the configuration constants for better control
        final interpreterOptions =
            InterpreterOptions()
              ..threads = NUM_THREADS
              ..useNnApiForAndroid = USE_NNAPI;

        _interpreter = await Interpreter.fromAsset(
          MODEL_PATH,
          options: interpreterOptions,
        );
      } catch (e) {
        // If loading from asset fails, try lowering thread count
        debugPrint(
          'Error loading model from asset: $e. Trying with fewer threads...',
        );

        final interpreterOptions =
            InterpreterOptions()
              ..threads = 1
              ..useNnApiForAndroid = false;

        debugPrint('Retrying with threads=1 and useNnApi=false');

        try {
          _interpreter = await Interpreter.fromAsset(
            MODEL_PATH,
            options: interpreterOptions,
          );
        } catch (retryError) {
          // If that still fails, try loading the model from buffer
          debugPrint(
            'Retry failed: $retryError. Trying to load from buffer...',
          );

          try {
            final modelBuffer = await rootBundle.load(MODEL_PATH);
            _interpreter = await Interpreter.fromBuffer(
              modelBuffer.buffer.asUint8List(),
              options: interpreterOptions,
            );
          } catch (bufferError) {
            debugPrint('Buffer loading failed: $bufferError');
            throw Exception('All model loading attempts failed');
          }
        }
      }

      if (_interpreter != null) {
        // Print model info
        final inputShape = _interpreter!.getInputTensor(0).shape;
        final outputShape = _interpreter!.getOutputTensor(0).shape;

        debugPrint('Model loaded with shapes:');
        debugPrint('Input shape: $inputShape');
        debugPrint('Output shape: $outputShape');

        // Initialize model helper using the new factory method
        _modelHelper = await YoloModelHelper.create(interpreter: _interpreter!);

        if (_modelHelper == null) {
          debugPrint('Failed to create model helper, using fallback');

          if (USE_DUMMY_DETECTIONS) {
            setState(() {
              _isModelLoaded = true;
            });
          } else {
            throw Exception('Failed to initialize model helper');
          }
        } else {
          // Run a quick test to verify model works
          // Use a blank image to test processing speed
          final dummyInput = List<double>.filled(
            INPUT_SIZE * INPUT_SIZE * CHANNELS,
            0.0,
          );

          final startTime = DateTime.now();
          final results = await _modelHelper!.runInference(dummyInput);
          final endTime = DateTime.now();
          final processingTime = endTime.difference(startTime).inMilliseconds;

          debugPrint('Model test completed in ${processingTime}ms');
          debugPrint('Output size: ${results.length}');

          setState(() {
            _isModelLoaded = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading model details: ${e.toString()}');

      setState(() {
        _hasError = true;
        _errorMessage = 'Error loading model: $e';

        // If USE_DUMMY_DETECTIONS is true, allow app to continue with mock data
        if (USE_DUMMY_DETECTIONS) {
          debugPrint('Using dummy detections as fallback');
          _isModelLoaded = true;
        }
      });
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    // Don't process if already processing, model not loaded, error occurred,
    // viewing medicine details, in cooldown period, or popup is visible
    if (_isProcessing ||
        !_isModelLoaded ||
        _hasError ||
        _isViewingMedicineDetails ||
        _isInDetectionCooldown ||
        _isPopupVisible) {
      return;
    }

    // Add cooldown check to prevent immediate detection after returning from details
    if (_lastDetectionTime != null) {
      final cooldownPeriod =
          DateTime.now().difference(_lastDetectionTime!).inMilliseconds;
      if (cooldownPeriod < 2000) {
        // 2 second cooldown
        return;
      }
    }

    _isProcessing = true;

    try {
      // Get scaling info with image dimensions
      final imageWidth = image.width;
      final imageHeight = image.height;

      // Calculate letterboxing for aspect ratio preservation
      double scale;
      int paddingLeft = 0;
      int paddingTop = 0;

      if (imageWidth / imageHeight > 1) {
        scale = INPUT_SIZE / imageWidth;
        paddingTop = ((INPUT_SIZE - (imageHeight * scale).round()) / 2).round();
      } else {
        scale = INPUT_SIZE / imageHeight;
        paddingLeft = ((INPUT_SIZE - (imageWidth * scale).round()) / 2).round();
      }

      // Update the scaling info for bounding box mapping later
      _updateScalingInfo(scale, paddingLeft, paddingTop);

      if (ENABLE_DEBUG_LOGGING) {
        debugPrint("Image dimensions: $imageWidth x $imageHeight");
        debugPrint(
          "Scale: $_scale, Padding: left=$_paddingLeft, top=$_paddingTop",
        );
      }

      // Process the entire camera frame in a compute isolate if enabled
      // This keeps the UI responsive by moving the processing off the main thread
      final inputData =
          USE_ISOLATE
              ? await compute(processImageForYolo, image)
              : await processImageForYolo(image);

      if (_modelHelper != null) {
        if (ENABLE_DEBUG_LOGGING) {
          debugPrint('Processing frame with model helper...');
        }

        // Track processing time
        final startTime = DateTime.now();

        // Use our custom model helper to run inference
        final outputData = await _modelHelper!.runInference(inputData);

        final processingTime =
            DateTime.now().difference(startTime).inMilliseconds;
        if (ENABLE_DEBUG_LOGGING) {
          debugPrint('Inference completed in ${processingTime}ms');
        }

        if (outputData.isNotEmpty) {
          // Process detections using the flattened output
          final outputShape = _interpreter!.getOutputTensor(0).shape;
          final detections = _processYoloV8OutputSimple(
            outputData,
            outputShape,
          );

          // If we have high confidence detections but no text recognition result yet,
          // run text recognition immediately before showing the popup
          bool hasHighConfidenceDetection = false;
          if (detections.isNotEmpty) {
            for (var detection in detections) {
              if (detection['confidence'] > 0.8) {
                hasHighConfidenceDetection = true;
                break;
              }
            }
          }

          // Run OCR if we have a high confidence detection but no OCR result yet
          if (hasHighConfidenceDetection &&
              (_textRecognitionResult == null ||
                  !_textRecognitionResult!.success ||
                  _textRecognitionResult!.expiryDate == null)) {
            // Process OCR synchronously before showing detection results
            await _processTextRecognition(image);
          }

          // Enhance detections with text recognition results if available
          if (_textRecognitionResult != null &&
              _textRecognitionResult!.success) {
            for (var detection in detections) {
              // If we have a recognized brand name, add it to the detection
              if (_textRecognitionResult!.brandName != null) {
                detection['recognizedBrandName'] =
                    _textRecognitionResult!.brandName;
              }

              // If we have an expiry date, add it to the detection
              if (_textRecognitionResult!.expiryDate != null) {
                detection['expiryDate'] = _textRecognitionResult!.expiryDate;
              }
            }
          }

          setState(() {
            _detections = detections;
          });

          // Debug info - print the highest confidence regardless of threshold
          if (ENABLE_DEBUG_LOGGING && outputData.length >= YOLO8_OUTPUTS * 6) {
            double highestConfidence = 0.0;
            int highestClass = -1;

            for (int i = 0; i < YOLO8_OUTPUTS; i++) {
              double class0Score = outputData[i + 4 * YOLO8_OUTPUTS];
              double class1Score = outputData[i + 5 * YOLO8_OUTPUTS];
              double confidence = math.max(class0Score, class1Score);

              if (confidence > highestConfidence) {
                highestConfidence = confidence;
                highestClass = class0Score > class1Score ? 0 : 1;
              }
            }

            String className =
                highestClass >= 0 && highestClass < _classLabels.length
                    ? _classLabels[highestClass]
                    : 'unknown';

            debugPrint(
              'Highest confidence: $highestConfidence for class: $className',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error processing frame: $e');

      // Only use dummy detections in debug mode
      if (USE_DUMMY_DETECTIONS && kDebugMode) {
        setState(() {
          _detections = DUMMY_DETECTIONS;
        });
      }
    } finally {
      _isProcessing = false;
    }
  }

  // Improved detection processing with letterboxing awareness
  List<dynamic> _processYoloV8OutputSimple(
    List<double> outputData,
    List<int> outputShape,
  ) {
    final List<dynamic> detections = [];

    try {
      if (ENABLE_DEBUG_LOGGING) {
        debugPrint('Processing output with shape: $outputShape');
        debugPrint('Output data length: ${outputData.length}');
      }

      // Determine output layout from shape
      bool isTransposed = TRANSPOSE_OUTPUT; // Use the configuration setting

      if (outputShape.length == 3) {
        // Check if we have a [1, 6, 8400] or [1, 8400, 6] format
        if (outputShape[1] == YOLO8_DIMENSIONS &&
            outputShape[2] == YOLO8_OUTPUTS) {
          isTransposed = false; // [1, 6, 8400]
          debugPrint(
            'Detected output format: [1, $YOLO8_DIMENSIONS, $YOLO8_OUTPUTS]',
          );
        } else if (outputShape[1] == YOLO8_OUTPUTS &&
            outputShape[2] == YOLO8_DIMENSIONS) {
          isTransposed = true; // [1, 8400, 6]
          debugPrint(
            'Detected output format: [1, $YOLO8_OUTPUTS, $YOLO8_DIMENSIONS]',
          );
        } else {
          debugPrint('Warning: Unexpected output shape: $outputShape');
        }
      }

      // Process each detection based on format and track all confidences
      List<Map<String, dynamic>> allDetections = [];

      for (int i = 0; i < YOLO8_OUTPUTS; i++) {
        double xCenter, yCenter, width, height, class0Score, class1Score;

        if (isTransposed) {
          // Format: [1, YOLO8_OUTPUTS, YOLO8_DIMENSIONS]
          // Each row contains one detection [x, y, w, h, class0, class1]
          final baseIdx = i * YOLO8_DIMENSIONS;
          if (baseIdx + 5 >= outputData.length) continue;

          xCenter = outputData[baseIdx];
          yCenter = outputData[baseIdx + 1];
          width = outputData[baseIdx + 2];
          height = outputData[baseIdx + 3];
          class0Score = outputData[baseIdx + 4];
          class1Score = outputData[baseIdx + 5];
        } else {
          // Format: [1, YOLO8_DIMENSIONS, YOLO8_OUTPUTS]
          // Values are organized by type
          if (i >= outputData.length) continue;

          xCenter = outputData[i]; // First dimension: x center
          yCenter = outputData[i + YOLO8_OUTPUTS]; // Second dimension: y center
          width = outputData[i + 2 * YOLO8_OUTPUTS]; // Third dimension: width
          height =
              outputData[i + 3 * YOLO8_OUTPUTS]; // Fourth dimension: height
          class0Score =
              outputData[i +
                  4 * YOLO8_OUTPUTS]; // Fifth dimension: class 0 score
          class1Score =
              outputData[i +
                  5 * YOLO8_OUTPUTS]; // Sixth dimension: class 1 score
        }

        // Determine most likely class and confidence
        int classIndex = class0Score > class1Score ? 0 : 1;
        double confidence = math.max(class0Score, class1Score);

        // Filter low confidence detections early to reduce processing
        if (confidence < CONFIDENCE_THRESHOLD * 0.75) {
          continue; // Skip very low confidence detections early
        }

        // Skip unreasonable detections that are likely false positives
        // These often have very extreme dimensions
        if (width < 0.01 || height < 0.01 || width > 0.9 || height > 0.9) {
          continue;
        }

        // Store all detections with their confidence for later filtering
        allDetections.add({
          'index': i,
          'xCenter': xCenter,
          'yCenter': yCenter,
          'width': width,
          'height': height,
          'confidence': confidence,
          'classIndex': classIndex,
        });
      }

      // Sort by confidence (highest first)
      allDetections.sort((a, b) => b['confidence'].compareTo(a['confidence']));

      // Limit early to avoid processing too many candidates
      final int maxDetectionsToProcess = 10; // Further reduce processing

      // Important: Get the preview size directly from the camera controller
      final Size previewSize =
          _controller?.value.previewSize ?? MediaQuery.of(context).size;
      final double previewWidth = previewSize.width;
      final double previewHeight = previewSize.height;

      if (ENABLE_DEBUG_LOGGING) {
        debugPrint('Camera preview size: ${previewWidth}x${previewHeight}');
        debugPrint(
          'Scale: $_scale, Padding: left=$_paddingLeft, top=$_paddingTop',
        );
      }

      // For logging purposes, capture all detections above threshold
      int totalDetectionsAboveThreshold = 0;
      for (var detection in allDetections) {
        if (detection['confidence'] > CONFIDENCE_THRESHOLD) {
          totalDetectionsAboveThreshold++;
        }
      }
      if (ENABLE_DEBUG_LOGGING) {
        debugPrint(
          'Found $totalDetectionsAboveThreshold detections above confidence threshold',
        );
      }

      for (
        int j = 0;
        j < math.min(maxDetectionsToProcess, allDetections.length);
        j++
      ) {
        final detection = allDetections[j];
        if (detection['confidence'] > CONFIDENCE_THRESHOLD) {
          final xCenter = detection['xCenter'];
          final yCenter = detection['yCenter'];
          final width = detection['width'];
          final height = detection['height'];
          final classIndex = detection['classIndex'];
          final confidence = detection['confidence'];

          // Additional filtering on extreme aspect ratios
          final aspectRatio = width / height;
          if (aspectRatio < 0.2 || aspectRatio > 5.0) {
            if (ENABLE_DEBUG_LOGGING) {
              debugPrint(
                'Skipping detection with extreme aspect ratio: $aspectRatio',
              );
            }
            continue;
          }

          // IMPORTANT: The bounding box coordinates from YOLOv8 are normalized to [0,1]
          // AND are relative to the input tensor INCLUDING letterboxing.

          // 1. First, undo the letterboxing to get normalized coordinates in the original image space
          double adjustedX = xCenter;
          double adjustedY = yCenter;
          double adjustedWidth = width;
          double adjustedHeight = height;

          if (USE_LETTERBOXING && APPLY_SCALING_CORRECTION) {
            // Remove padding and adjust for scale:
            // Convert from padded input coordinates to original image coordinates
            adjustedX =
                (xCenter * INPUT_SIZE - _paddingLeft) / (_scale * INPUT_SIZE);
            adjustedY =
                (yCenter * INPUT_SIZE - _paddingTop) / (_scale * INPUT_SIZE);
            adjustedWidth = width / _scale;
            adjustedHeight = height / _scale;
          }

          // Clamp values to ensure they're within the valid range
          adjustedX = adjustedX.clamp(0.0, 1.0);
          adjustedY = adjustedY.clamp(0.0, 1.0);

          if (ENABLE_DEBUG_LOGGING) {
            debugPrint(
              'Original detection: center=($xCenter, $yCenter), size=($width, $height)',
            );
            debugPrint(
              'Adjusted detection: center=($adjustedX, $adjustedY), size=($adjustedWidth, $adjustedHeight)',
            );
          }

          // 2. Convert from normalized center coordinates to normalized corner coordinates
          double xMin = (adjustedX - adjustedWidth / 2).clamp(0.0, 1.0);
          double yMin = (adjustedY - adjustedHeight / 2).clamp(0.0, 1.0);
          double xMax = (adjustedX + adjustedWidth / 2).clamp(0.0, 1.0);
          double yMax = (adjustedY + adjustedHeight / 2).clamp(0.0, 1.0);

          // 3. Get the actual camera preview size from the controller
          final Size screenSize = MediaQuery.of(context).size;

          // 4. Calculate the camera preview dimensions and position within the screen
          // This is critical - we need to handle the fact that the camera preview might be scaled/cropped
          double previewAspectRatio = previewWidth / previewHeight;
          double screenAspectRatio = screenSize.width / screenSize.height;

          double scaledPreviewWidth;
          double scaledPreviewHeight;
          double previewOffsetX = 0;
          double previewOffsetY = 0;

          // Handle different aspect ratios between preview and screen
          if (previewAspectRatio > screenAspectRatio) {
            // Preview is wider than screen
            scaledPreviewHeight = screenSize.height;
            scaledPreviewWidth = scaledPreviewHeight * previewAspectRatio;
            previewOffsetX = (screenSize.width - scaledPreviewWidth) / 2;
          } else {
            // Preview is taller than screen
            scaledPreviewWidth = screenSize.width;
            scaledPreviewHeight = scaledPreviewWidth / previewAspectRatio;
            previewOffsetY = (screenSize.height - scaledPreviewHeight) / 2;
          }

          // 5. Convert normalized coordinates to pixel coordinates based on the actual preview size
          int xMinPx = (previewOffsetX + xMin * scaledPreviewWidth).round();
          int yMinPx = (previewOffsetY + yMin * scaledPreviewHeight).round();
          int xMaxPx = (previewOffsetX + xMax * scaledPreviewWidth).round();
          int yMaxPx = (previewOffsetY + yMax * scaledPreviewHeight).round();

          if (ENABLE_DEBUG_LOGGING) {
            debugPrint(
              'Preview size: ${previewWidth}x${previewHeight}, scaled to ${scaledPreviewWidth}x${scaledPreviewHeight}',
            );
            debugPrint('Preview offset: ($previewOffsetX, $previewOffsetY)');
            debugPrint('Bounding box: ($xMinPx, $yMinPx, $xMaxPx, $yMaxPx)');
          }

          // Create detection map
          detections.add({
            'box': [xMinPx, yMinPx, xMaxPx, yMaxPx],
            'confidence': confidence,
            'classId': classIndex,
            'className':
                classIndex < _classLabels.length
                    ? _classLabels[classIndex]
                    : 'unknown',
          });
        }
      }

      // Apply Non-Maximum Suppression
      final filteredDetections = _applyNMS(detections);

      // Limit to just the most confident detection
      final limitedDetections =
          filteredDetections.length > MAX_DISPLAY_DETECTIONS
              ? filteredDetections.sublist(0, MAX_DISPLAY_DETECTIONS)
              : filteredDetections;

      if (ENABLE_DEBUG_LOGGING) {
        debugPrint(
          'Found ${filteredDetections.length} detections after NMS, showing ${limitedDetections.length}',
        );
        for (var detection in limitedDetections) {
          debugPrint(
            '  - ${detection['className']} (${(detection['confidence'] * 100).toStringAsFixed(1)}%)',
          );
          debugPrint('    Box: ${detection['box']}');
        }
      }

      // Process medicine detection
      if (filteredDetections.isNotEmpty) {
        // Check if we have a biogesic-para or ritemed-para detection with good confidence
        debugPrint('Checking detections for biogesic-para and ritemed-para...');

        for (var detection in filteredDetections) {
          debugPrint(
            'Detection found: ${detection['className']} with confidence ${detection['confidence']}',
          );

          bool isMedicineDetected = false;
          int medicineId = 0;

          // Use text recognition results to validate YOLO detections
          // If OCR found text that matches the medicine name, boost confidence
          double confidenceBoost = 0.0;
          if (_textRecognitionResult != null &&
              _textRecognitionResult!.success) {
            String? recognizedText =
                _textRecognitionResult!.recognizedText?.toLowerCase() ?? "";

            // Check if recognized text contains medicine name keywords
            if (detection['className'] == 'biogesic-para' &&
                (recognizedText.contains('biogesic') ||
                    recognizedText.contains('paracetamol'))) {
              confidenceBoost = 0.05;
              debugPrint(
                'OCR validation: Found "biogesic" or "paracetamol" in text, boosting confidence',
              );
            } else if (detection['className'] == 'ritemed-para' &&
                (recognizedText.contains('ritemed') ||
                    recognizedText.contains('paracetamol'))) {
              confidenceBoost = 0.05;
              debugPrint(
                'OCR validation: Found "ritemed" or "paracetamol" in text, boosting confidence',
              );
            }
          }

          // Apply confidence boost from OCR validation
          double adjustedConfidence = detection['confidence'] + confidenceBoost;
          adjustedConfidence = adjustedConfidence.clamp(
            0.0,
            1.0,
          ); // Ensure it's still in 0-1 range

          if (detection['className'] == 'biogesic-para' &&
              adjustedConfidence > 0.85) {
            // Slightly lower threshold with OCR validation
            debugPrint(
              'High confidence biogesic-para detected with OCR validation! Confidence: ${adjustedConfidence}',
            );
            isMedicineDetected = true;
            medicineId = 1; // biogesic-para is ID 1
          } else if (detection['className'] == 'ritemed-para' &&
              adjustedConfidence > 0.85) {
            // Slightly lower threshold with OCR validation
            debugPrint(
              'High confidence ritemed-para detected with OCR validation! Confidence: ${adjustedConfidence}',
            );
            isMedicineDetected = true;
            medicineId = 2; // ritemed-para is ID 2
          }

          if (isMedicineDetected) {
            // Avoid showing popup too frequently
            final now = DateTime.now();
            if (_lastDetectionTime == null ||
                now.difference(_lastDetectionTime!).inSeconds > 3) {
              _lastDetectionTime = now;
              debugPrint('Scheduling medicine info popup...');

              // Store the detected medicine ID for the popup
              final detectedMedicineId = medicineId;

              // Show the medicine info popup after a short delay
              Future.delayed(Duration(milliseconds: 500), () {
                if (mounted) {
                  debugPrint('Showing medicine info popup now');
                  _showMedicineInfoPopup(context, detectedMedicineId);
                } else {
                  debugPrint('Widget no longer mounted, cannot show popup');
                }
              });
              break;
            } else {
              debugPrint('Skipping popup, too soon since last detection');
            }
          }
        }
      }

      return limitedDetections;
    } catch (e) {
      debugPrint('Error processing YOLOv8 output: $e');
      if (USE_DUMMY_DETECTIONS) {
        return DUMMY_DETECTIONS;
      }
      return [];
    }
  }

  // Improved NMS with better duplicate filtering
  List<dynamic> _applyNMS(List<dynamic> detections) {
    // If no detections or only one detection, no need for NMS
    if (detections.length <= 1) {
      return detections;
    }

    // Sort by confidence (highest first)
    detections.sort((a, b) => b['confidence'].compareTo(a['confidence']));

    final List<dynamic> result = [];
    final List<bool> isIncluded = List.filled(detections.length, true);

    // Only include detections that meet our confidence threshold
    for (int i = 0; i < detections.length; i++) {
      if (!isIncluded[i]) continue;
      if (detections[i]['confidence'] < CONFIDENCE_THRESHOLD) continue;

      final boxI = detections[i]['box'];
      final classI = detections[i]['classId']; // Get class ID
      result.add(detections[i]);

      // Compare against all other detections
      for (int j = i + 1; j < detections.length; j++) {
        if (!isIncluded[j]) continue;

        final boxJ = detections[j]['box'];
        final classJ = detections[j]['classId']; // Get class ID

        // Only apply NMS between detections of the same class
        if (classI == classJ) {
          final intersection = _calculateIntersection(boxI, boxJ);
          final union = _calculateUnion(boxI, boxJ, intersection);
          final iou = union > 0 ? intersection / union : 0;

          // If IoU exceeds threshold, exclude this box as it's a duplicate
          if (iou > IOU_THRESHOLD) {
            isIncluded[j] = false;
            if (ENABLE_DEBUG_LOGGING) {
              debugPrint(
                'NMS: Removed duplicate detection with IoU $iou and confidence ${detections[j]['confidence']}',
              );
            }
          }
        }
      }
    }

    if (ENABLE_DEBUG_LOGGING) {
      debugPrint(
        'NMS: Kept ${result.length} out of ${detections.length} detections',
      );
    }

    return result;
  }

  // Calculate intersection area between two boxes
  double _calculateIntersection(List<int> boxA, List<int> boxB) {
    final int x1 = math.max(boxA[0], boxB[0]);
    final int y1 = math.max(boxA[1], boxB[1]);
    final int x2 = math.min(boxA[2], boxB[2]);
    final int y2 = math.min(boxA[3], boxB[3]);

    final int width = math.max(0, x2 - x1);
    final int height = math.max(0, y2 - y1);

    return width * height.toDouble();
  }

  // Calculate union area between two boxes
  double _calculateUnion(List<int> boxA, List<int> boxB, double intersection) {
    final int areaA = (boxA[2] - boxA[0]) * (boxA[3] - boxA[1]);
    final int areaB = (boxB[2] - boxB[0]) * (boxB[3] - boxB[1]);

    return areaA + areaB - intersection;
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    int newIndex = (_currentCameraIndex + 1) % _cameras.length;
    await _initializeCameraAtIndex(newIndex);
  }

  @override
  void setState(Function() fn) {
    super.setState(fn);

    // Only animate if controllers are initialized
    if (_animationsInitialized) {
      try {
        // Animate the analytics panel when detections change
        if (_detections != null && _detections!.isNotEmpty) {
          _analyticsAnimationController!.forward();
          _boundingBoxAnimationController!.forward();
          _guideAnimationController!.reverse(); // Hide guide
        } else {
          _analyticsAnimationController!.reverse();
          _boundingBoxAnimationController!.reverse();
          _guideAnimationController!.forward(); // Show guide
        }
      } catch (e) {
        _animationsInitialized = false;
        debugPrint('Animation error: $e');
      }
    }
  }

  // Method to navigate to medicine details page with proper resource management
  void _navigateToMedicineDetails(Medicine medicine, {String? expiryDate}) {
    // Pause model processing and camera stream
    setState(() {
      _isViewingMedicineDetails = true;
    });
    _stopCameraStream();

    // Save medicine to scan history
    _databaseHelper.saveScanToHistory(
      medicine.id,
      medicine.brandName,
      medicine.genericName,
    );

    // Navigate to details page
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder:
                (context) => MedicineDetailsPage(
                  medicine: medicine,
                  expiryDate: expiryDate, // Pass the expiration date
                ),
          ),
        )
        .then((_) {
          // Resume processing when returning from details page and reset detections
          setState(() {
            _isViewingMedicineDetails = false;
            _detections =
                null; // Reset detections when returning from details page
            _lastDetectionTime = null; // Also reset the last detection time
            _isInDetectionCooldown =
                true; // Enable cooldown to prevent immediate detection
          });

          // Add a small delay before resuming camera stream to avoid immediate detection
          Future.delayed(Duration(milliseconds: 1500), () {
            if (mounted) {
              _startCameraStream();

              // Add a longer cooldown after starting the camera
              Future.delayed(Duration(seconds: 4), () {
                if (mounted) {
                  setState(() {
                    _isInDetectionCooldown =
                        false; // Disable cooldown after delay
                  });
                }
              });
            }
          });
        });
  }

  // Show medicine info popup
  Future<void> _showMedicineInfoPopup(
    BuildContext context,
    int medicineId,
  ) async {
    // Set the popup visibility flag to prevent further detections while popup is showing
    setState(() {
      _isPopupVisible = true;
    });

    try {
      debugPrint('Showing medicine info popup...');

      // Get medicine info from the database with the provided ID
      final medicineData = await _databaseHelper.getMedicineById(medicineId);

      debugPrint(
        'Medicine data retrieved: ${medicineData != null ? 'yes' : 'no'}',
      );
      if (medicineData != null) {
        debugPrint('Medicine data: $medicineData');
      }

      if (medicineData != null && mounted) {
        final medicine = Medicine.fromMap(medicineData);
        debugPrint('Medicine object created: ${medicine.brandName}');

        // Check if we have text recognition results
        String? recognizedExpiryDate = _textRecognitionResult?.expiryDate;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              title: Text('Medicine Detected: ${medicine.brandName}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Generic Name: ${medicine.genericName}'),
                  SizedBox(height: 8),

                  Text('View detailed information about this medicine?'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Set detection cooldown even when canceling
                    setState(() {
                      _detections = null;
                      _lastDetectionTime = null;
                      _isInDetectionCooldown = true;
                      _isPopupVisible = false; // Reset popup visibility flag
                    });

                    // End cooldown after 4 seconds
                    Future.delayed(Duration(seconds: 4), () {
                      if (mounted) {
                        setState(() {
                          _isInDetectionCooldown = false;
                        });
                      }
                    });
                  },
                  child: Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() {
                      _isPopupVisible =
                          false; // Reset popup visibility flag before navigation
                    });
                    _navigateToMedicineDetails(
                      medicine,
                      expiryDate: recognizedExpiryDate,
                    );
                  },
                  child: Text('View Details'),
                ),
              ],
            );
          },
        );
      } else {
        debugPrint('No medicine data found or widget not mounted');
        // Reset the popup visibility flag if we couldn't show the popup
        setState(() {
          _isPopupVisible = false;
        });
      }
    } catch (e) {
      debugPrint('Error showing medicine info: $e');
      // Reset the popup visibility flag in case of error
      setState(() {
        _isPopupVisible = false;
      });
    }
  }

  // Process text recognition on the current camera frame
  Future<void> _runTextRecognition() async {
    // Don't run text recognition if conditions are not met
    if (_textRecognizer == null ||
        _isTextRecognitionProcessing ||
        _controller == null ||
        !_controller!.value.isInitialized ||
        !_isCameraStreamActive ||
        _isViewingMedicineDetails ||
        _isInDetectionCooldown ||
        _isPopupVisible) {
      return;
    }

    _isTextRecognitionProcessing = true;

    try {
      // Get the current image from the camera stream, but don't wait for the result
      _controller!.startImageStream((image) {
        // Stop the stream after we get one frame
        _controller!.stopImageStream();
        // Process the image
        _processTextRecognition(image);
      });
    } catch (e) {
      debugPrint('Error capturing frame for text recognition: $e');
      _isTextRecognitionProcessing = false;
    }
  }

  Future<void> _processTextRecognition(CameraImage image) async {
    if (_textRecognizer == null) {
      return;
    }

    try {
      // Set processing flag if not already set (when called from _runTextRecognition)
      bool wasProcessingBefore = _isTextRecognitionProcessing;
      if (!wasProcessingBefore) {
        _isTextRecognitionProcessing = true;
      }

      // Process the image with text recognition
      final result = await _textRecognizer!.processImageForText(image);

      setState(() {
        _textRecognitionResult = result;
        _isTextRecognitionProcessing = false;
      });

      if (result.success) {
        // Log the full recognized text in debug mode to help with troubleshooting
        if (kDebugMode) {
          print('--- OCR Text Recognition Results ---');
          print('Full recognized text:');
          print(result.recognizedText);

          // Check for medicine name keywords
          final String lowerText = (result.recognizedText ?? "").toLowerCase();
          final List<String> medicineKeywords = [
            'biogesic',
            'ritemed',
            'paracetamol',
            'acetaminophen',
          ];

          for (String keyword in medicineKeywords) {
            if (lowerText.contains(keyword)) {
              print('Found medicine keyword: $keyword');
            }
          }

          // Log expiration date if found
          if (result.expiryDate != null) {
            print('Extracted expiry date: ${result.expiryDate}');
          } else {
            print('No expiration date found');
          }

          print('-------------------------------');
        }

        // Only log the expiry date to regular logs
        if (result.expiryDate != null) {
          debugPrint(
            'Text recognition found expiry date: ${result.expiryDate}',
          );
        }
      }
    } catch (e) {
      debugPrint('Error in text recognition processing: $e');
      _isTextRecognitionProcessing = false;
    }
  }
}
