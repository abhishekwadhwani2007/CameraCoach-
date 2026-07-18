import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/pose_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/photo_quality_analyzer.dart';
import '../../services/silhouette_generator.dart';
import '../../utils/logger.dart';

class PoseConfirmationScreen extends StatefulWidget {
  final String imagePath;
  final String? overlayPath;

  const PoseConfirmationScreen({
    super.key,
    required this.imagePath,
    this.overlayPath,
  });

  @override
  State<PoseConfirmationScreen> createState() => _PoseConfirmationScreenState();
}

class _PoseConfirmationScreenState extends State<PoseConfirmationScreen> {
  bool _isProcessing = true;
  bool _isSaving = false;
  Map<String, dynamic>? _landmarks;
  String? _outlinePath;
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _processImage();
  }

  Future<void> _processImage() async {
    AppLogger.debug('PoseConfirmationScreen: received overlayPath: ${widget.overlayPath != null ? "present" : "null"}');
    try {
      final file = File(widget.imagePath);
      final decodedImage = await decodeImageFromList(file.readAsBytesSync());

      setState(() {
        _imageSize = Size(
          decodedImage.width.toDouble(),
          decodedImage.height.toDouble(),
        );
      });

      final poses = await PoseService.detectPose(widget.imagePath);
      PoseService.dispose();
      if (poses.isNotEmpty) {
        final landmarks = PoseService.poseToMap(poses.first);
        final outline = widget.overlayPath ??
            await SilhouetteGenerator.generate(
              imagePath: widget.imagePath,
              landmarks: landmarks,
            );
        if (outline != null) {
          final provider = FileImage(File(outline));
          await provider.evict();
        }
        setState(() {
          _landmarks = landmarks;
          _outlinePath = outline;
        });
      }
    } catch (e) {
      AppLogger.error('Error processing pose image: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _saveReference() async {
    if (_landmarks == null) return;

    setState(() => _isSaving = true);

    try {
      final proSettingsJson =
          await PhotoQualityAnalyzer.analyzeJson(widget.imagePath);
      
      AppLogger.debug('PoseConfirmationScreen: saving with outlinePath: ${_outlinePath != null ? "present" : "null"}');
      await LocalStorageService.saveReference(
        originalImagePath: widget.imagePath,
        keypointsJson: jsonEncode(_landmarks),
        width: _imageSize!.width,
        height: _imageSize!.height,
        outlinePath: _outlinePath,
        proSettingsJson: proSettingsJson,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reference saved successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      AppLogger.error('Failed to save reference: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('An error occurred while saving. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Pose'),
        actions: [
          if (!_isProcessing && _landmarks != null)
            TextButton(
              onPressed: _isSaving ? null : _saveReference,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('SAVE'),
            ),
        ],
      ),
      body: Stack(
        children: [
          Container(color: Colors.black),
          if (_imageSize != null)
            Center(
              child: AspectRatio(
                aspectRatio: _imageSize!.width / _imageSize!.height,
                child: Image.file(
                  File(widget.imagePath),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          if (!_isProcessing && _outlinePath != null && _imageSize != null)
            Center(
              child: AspectRatio(
                aspectRatio: _imageSize!.width / _imageSize!.height,
                child: Image.file(
                  File(_outlinePath!),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          if (_isProcessing)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Detecting Pose...',
                      style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          if (!_isProcessing && _landmarks == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'Human not detected.\n\nAI Coach Tip: Please use a photo where the person is standing and visible from head to toe! 🧍',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Colors.white, fontSize: 18, height: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
