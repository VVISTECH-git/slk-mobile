import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../theme/app_theme.dart';
import '../../widgets/theme_button.dart';
import '../../widgets/ui/ui.dart' show showError;

/// Full-screen camera barcode/QR scanner. Pops with the first decoded string.
/// Used by POS (add to cart) and stock/transfer pickers (find a variant).
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key, this.title = 'Scan barcode'});
  final String title;

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.all],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (code == null) return;
    _handled = true;
    Navigator.of(context).pop(code);
  }

  /// A label photographed earlier — a picture someone sent, a screenshot —
  /// read from the photo library instead of the camera.
  Future<void> _fromPhotos() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final capture = await _controller.analyzeImage(picked.path);
    if (!mounted) return;
    if (capture == null || capture.barcodes.every((b) => b.rawValue == null || b.rawValue!.isEmpty)) {
      showError(context, 'No QR code or barcode could be read in that photo. Try a closer, sharper one.');
      return;
    }
    _onDetect(capture);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          const ThemeButton(),
          IconButton(
            onPressed: _fromPhotos,
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Read from a photo',
          ),
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_outlined),
          ),
          IconButton(
            onPressed: () => _controller.switchCamera(),
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Simple reticle overlay.
          Container(
            height: 220,
            width: 260,
            decoration: BoxDecoration(
              border: Border.all(color: context.p.accent, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const Positioned(
            bottom: 48,
            child: Text('Point the camera at a barcode, or pick a photo of one',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
