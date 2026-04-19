---
name: flutter-imaging
description: >
  Flutter image processing skill — use this whenever the project involves image
  capture, analysis, transformation, filtering, computer vision, OCR, object
  detection, pixel manipulation, or any mathematically intensive image pipeline.
  Triggers on mentions of camera, image processing, pixel, convolution, filter,
  histogram, segmentation, ML Kit, TFLite, ONNX, OpenCV, image annotation,
  photo inspection, defect detection, image overlay, or image comparison.
  Always apply alongside flutter-core. Requires advanced mathematics: matrix
  operations, convolutions, Fourier transforms, linear algebra, statistics.
---

# Flutter Imaging Skill

> Always apply **flutter-core** in parallel. This skill extends it for imaging.

## Core Stack

| Package | Purpose |
|---|---|
| `image: ^4.5.0` | Pure Dart pixel-level manipulation: filters, transforms, codecs |
| `camera: ^0.11.0` | Camera stream access (iOS, Android; Chrome on web) |
| `image_picker: ^1.1.0` | Gallery/camera pick with permission handling |
| `google_mlkit_commons` | ML Kit base — text recognition, face detection, object detection |
| `google_mlkit_text_recognition` | OCR for Latin + CJK + Devanagari |
| `google_mlkit_object_detection` | On-device object detection & tracking |
| `tflite_flutter: ^0.10.4` | TFLite inference — custom models, iOS + Android |
| `flutter_isolate` | Background isolates for heavy compute |
| `photo_view: ^0.15.0` | Pinch-zoom image viewer |

---

## Mathematics Requirements

Image processing is applied linear algebra and signal processing. Never skip the math:

### Convolution — The Foundation of Image Filters
A filter kernel K applied to image I at pixel (x, y):

```
(I * K)(x,y) = Σᵢ Σⱼ I(x+i, y+j) · K(i, j)
```

Common 3×3 kernels:

```dart
// Sharpen
const sharpen = [
   0, -1,  0,
  -1,  5, -1,
   0, -1,  0,
];

// Gaussian blur (3×3, sigma≈1)
const gaussianBlur = [
  1/16, 2/16, 1/16,
  2/16, 4/16, 2/16,
  1/16, 2/16, 1/16,
];

// Sobel edge detection — horizontal gradient
const sobelX = [
  -1, 0, 1,
  -2, 0, 2,
  -1, 0, 1,
];

// Laplacian (edge detection)
const laplacian = [
   0,  1,  0,
   1, -4,  1,
   0,  1,  0,
];
```

### Pixel Color Space Conversions

```dart
import 'package:image/image.dart' as img;

/// RGB → Grayscale (luminance-weighted, perceptually accurate)
/// Uses ITU-R BT.601 coefficients
int rgbToGray(int r, int g, int b) =>
    (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);

/// RGB → HSV (Hue: 0-360, Saturation: 0-1, Value: 0-1)
({double h, double s, double v}) rgbToHsv(int r, int g, int b) {
  final rf = r / 255, gf = g / 255, bf = b / 255;
  final max = [rf, gf, bf].reduce((a, b) => a > b ? a : b);
  final min = [rf, gf, bf].reduce((a, b) => a < b ? a : b);
  final delta = max - min;

  double h = 0;
  if (delta != 0) {
    if (max == rf) h = 60 * ((gf - bf) / delta % 6);
    else if (max == gf) h = 60 * ((bf - rf) / delta + 2);
    else h = 60 * ((rf - gf) / delta + 4);
  }

  final s = max == 0 ? 0.0 : delta / max;
  return (h: h < 0 ? h + 360 : h, s: s, v: max);
}
```

### Histogram & Histogram Equalization

```dart
/// Compute grayscale histogram (256 bins) from img.Image
List<int> computeHistogram(img.Image image) {
  final hist = List<int>.filled(256, 0);
  for (final pixel in image) {
    final gray = rgbToGray(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
    hist[gray]++;
  }
  return hist;
}

/// Histogram equalization — improves contrast in low-light images
img.Image equalizeHistogram(img.Image src) {
  final hist = computeHistogram(src);
  final total = src.width * src.height;

  // Cumulative distribution function
  final cdf = List<int>.filled(256, 0);
  cdf[0] = hist[0];
  for (int i = 1; i < 256; i++) cdf[i] = cdf[i - 1] + hist[i];

  final cdfMin = cdf.firstWhere((v) => v > 0);
  final lut = List<int>.generate(256,
    (i) => ((cdf[i] - cdfMin) / (total - cdfMin) * 255).round().clamp(0, 255));

  final result = img.Image(width: src.width, height: src.height);
  for (final pixel in src) {
    final gray = rgbToGray(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
    final eq = lut[gray];
    result.setPixelRgb(pixel.x, pixel.y, eq, eq, eq);
  }
  return result;
}
```

---

## Isolate Pipeline Pattern

All image processing that takes >16ms must run off the UI thread. Use `compute()` for simple cases, full isolates for streaming.

```dart
// Single-shot processing (compute = managed isolate)
Future<Uint8List> applyFilterAsync(Uint8List inputBytes) {
  return compute(_processImageIsolate, inputBytes);
}

// Top-level function (required for compute — no closures)
Uint8List _processImageIsolate(Uint8List bytes) {
  final image = img.decodeImage(bytes)!;
  // Heavy processing here — runs on background thread
  final gray = img.grayscale(image);
  final sharpened = img.convolution(gray, filter: sharpen, div: 1, offset: 0);
  return Uint8List.fromList(img.encodePng(sharpened));
}
```

```dart
// Controller integrating with GetX
class ImageController extends GetxController {
  final processedImage = Rxn<Uint8List>();
  final isProcessing = false.obs;

  Future<void> processImage(Uint8List rawBytes) async {
    isProcessing.value = true;
    try {
      processedImage.value = await applyFilterAsync(rawBytes);
    } catch (e) {
      Get.snackbar('Error', 'Image processing failed: $e');
    } finally {
      isProcessing.value = false;
    }
  }
}
```

---

## Camera Stream → ML Pipeline

Critical: camera stream format varies by device. Always handle format conversion.

```dart
import 'package:camera/camera.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

class CameraMLController extends GetxController {
  CameraController? cameraController;
  bool _isProcessing = false;

  Future<void> initCamera() async {
    final cameras = await availableCameras();
    cameraController = CameraController(
      cameras.first,
      ResolutionPreset.high,
      imageFormatGroup: ImageFormatGroup.nv21, // Android: nv21; iOS: bgra8888
    );
    await cameraController!.initialize();
    cameraController!.startImageStream(_processCameraFrame);
  }

  void _processCameraFrame(CameraImage frame) {
    if (_isProcessing) return; // drop frames — never queue them
    _isProcessing = true;

    // Convert CameraImage to InputImage for ML Kit
    final inputImage = _cameraImageToInputImage(frame);
    if (inputImage != null) {
      _runDetection(inputImage).then((_) => _isProcessing = false);
    } else {
      _isProcessing = false;
    }
  }

  InputImage? _cameraImageToInputImage(CameraImage frame) {
    final camera = cameraController!.description;
    final rotation = InputImageRotationValue.fromRawValue(
      camera.sensorOrientation,
    );
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(frame.format.raw);
    if (format == null) return null;

    final plane = frame.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _runDetection(InputImage inputImage) async {
    // Implement ML Kit recognition here
  }

  @override
  void onClose() {
    cameraController?.stopImageStream();
    cameraController?.dispose();
    super.onClose();
  }
}
```

---

## ML Kit Integration

### Text Recognition (OCR)

```dart
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService extends GetxService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<OcrResult> recognizeText(InputImage image) async {
    try {
      final recognized = await _recognizer.processImage(image);
      final text = recognized.text;
      final blocks = recognized.blocks.map((b) => OcrBlock(
        text: b.text,
        boundingBox: b.boundingBox,
        confidence: b.confidence,
      )).toList();
      return OcrResult(fullText: text, blocks: blocks);
    } catch (e) {
      throw OcrException('OCR failed: $e');
    }
  }

  @override
  void onClose() {
    _recognizer.close();
    super.onClose();
  }
}
```

---

## Image Quality Assessment

For inspection apps: compute sharpness before accepting a photo.

```dart
/// Laplacian variance — measures image sharpness.
/// Higher = sharper. Threshold typically ~100 for field photos.
double computeSharpness(img.Image image) {
  final gray = img.grayscale(image);
  double sum = 0, sumSq = 0;
  int count = 0;

  for (int y = 1; y < gray.height - 1; y++) {
    for (int x = 1; x < gray.width - 1; x++) {
      final lap =
          gray.getPixel(x, y - 1).r +
          gray.getPixel(x - 1, y).r +
          gray.getPixel(x + 1, y).r +
          gray.getPixel(x, y + 1).r -
          4 * gray.getPixel(x, y).r;
      sum += lap.toDouble();
      sumSq += lap * lap;
      count++;
    }
  }
  final mean = sum / count;
  return sumSq / count - mean * mean; // variance
}

bool isImageSharp(img.Image image, {double threshold = 100}) =>
    computeSharpness(image) >= threshold;
```

---

## Performance Rules for Imaging

1. **Isolates for everything** — any image decode/encode/transform > 1ms goes in `compute()`.
2. **Drop camera frames** — never queue; process only if previous frame is done.
3. **Format awareness** — Android: `nv21`; iOS: `bgra8888`; web: JPEG only via `camera_web`.
4. **Resolution presets** — use `ResolutionPreset.medium` for ML pipelines; `high`/`veryHigh` only for capture.
5. **Memory** — call `img.decodeImage()` lazily; dispose `CameraController` in `onClose()`.
6. **Web limitations** — `dart:io` unavailable on web; use `Uint8List` + `img` package (pure Dart) for cross-platform pipelines.

---

## Reference Files

- `references/tflite-integration.md` — Custom TFLite model loading, input/output tensor handling, quantization
- `references/image-formats.md` — Format conversion charts: CameraImage YUV/NV21/BGRA → RGB, encode/decode performance
