/// Configuration constants for the TFLite model

// Input configuration
const int INPUT_SIZE = 640; // Input size for YOLOv8 (640x640)
const int CHANNELS = 3; // RGB channels
const double MEAN = 0.0; // Mean for normalization
const double STD = 255.0; // Standard deviation for normalization

// Output configuration for YOLOv8
// YOLOv8 outputs a tensor of shape [1, 84, 8400] where:
// - 84 = 4 (box coords) + 80 (class scores) or fewer classes if custom model
// - For this model with 2 classes: 4 (box coords) + 2 (class scores) = 6
// - 8400 = number of possible detections
const int NUM_CLASSES =
    2; // Number of classes (Biogesic-Paracetamol, Ritemed-Paracetamol)
const int YOLO8_OUTPUTS =
    8400; // Standard YOLOv8 detection count (may vary by model size)
const int YOLO8_DIMENSIONS = 6; // 4 bbox coords + 2 class probabilities

// Alternative formats - some models use different layouts
// Based on the model output shape [1, 6, 8400], we need to set this to false
const bool TRANSPOSE_OUTPUT =
    false; // Set to false since model outputs [1, 6, 8400]

// Detection parameters
// Optimized for thesis demonstration - better visible results
const double CONFIDENCE_THRESHOLD =
    0.80; // High threshold to only detect good confidence matches
const double IOU_THRESHOLD =
    0.65; // Higher IoU threshold to avoid duplicate detections

// Enable scaling correction to improve bounding box accuracy
const bool USE_LETTERBOXING = true; // Preserve aspect ratio with letterboxing
const bool APPLY_SCALING_CORRECTION =
    true; // Apply post-processing scaling correction

// Model file paths - use the float32 version for better precision and performance
const String MODEL_PATH = 'assets/best_float32.tflite'; // Verify exact filename
const String LABELS_PATH = 'assets/classes.txt';

// Fallback options for model loading issues - critical for Android
// Make this true to ensure the app can at least run with mock data
const bool USE_DUMMY_DETECTIONS =
    false; // Disable dummy detections to see only real results
const bool ENABLE_DEBUG_LOGGING = true; // Enable verbose debug logging

// Dummy detections for testing (only used if USE_DUMMY_DETECTIONS is true)
final List<Map<String, dynamic>> DUMMY_DETECTIONS = [
  {
    'box': [100, 100, 300, 300],
    'confidence': 0.85,
    'classId': 0,
    'className': 'Biogesic-Paracetamol',
  },
  {
    'box': [350, 150, 550, 350],
    'confidence': 0.75,
    'classId': 1,
    'className': 'Ritemed-Paracetamol',
  },
];

// Performance settings
const bool USE_ISOLATE =
    true; // Use compute isolate for better UI responsiveness
const int MAX_DETECTIONS_PER_FRAME =
    3; // Limit number of detections to avoid lag

// Display settings optimized for thesis presentation
const int MAX_DISPLAY_DETECTIONS =
    1; // Maximum number of detections to show on screen
const double BOX_THICKNESS = 4.0; // Increased thickness for better visibility
const double TEXT_SIZE = 18.0; // Increased text size for better readability

// Advanced TensorFlow Lite options
// If you encounter issues, consider setting these differently
const bool USE_NNAPI =
    false; // Neural Network API can cause issues on some devices
const int NUM_THREADS = 2; // Lower thread count may help on some devices
