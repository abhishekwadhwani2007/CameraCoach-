import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../review/pose_confirmation_screen.dart';
import '../live_session/live_coaching_screen.dart';
import '../../services/local_storage_service.dart';
import '../../services/backend_api_service.dart';
import '../../models/reference_model.dart';
import '../../core/theme.dart';
import '../../utils/logger.dart';

/// HomeScreen — Entry point for selecting target pose and starting live session.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickReferencePhoto() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (image == null || !mounted) return;

    const allowedExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
    final ext = image.path.split('.').last.toLowerCase();
    if (!allowedExtensions.contains('.$ext')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose a JPEG, PNG, or WebP image.'),
        ),
      );
      return;
    }

    const maxBytes = 10 * 1024 * 1024; // 10 MB
    final fileSize = await File(image.path).length();
    if (!mounted) return;
    if (fileSize > maxBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image is too large. Please choose a photo under 10 MB.'),
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Generating Coach...'),
          ],
        ),
      ),
    );

    AppLogger.debug('Sending image to API: ${image.path}');
    final overlayPath = await BackendApiService.generateOverlay(image.path);
    AppLogger.debug('generateOverlay returned: ${overlayPath != null ? 'path' : 'null'}');

    if (!mounted) return;
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PoseConfirmationScreen(
          imagePath: image.path,
          overlayPath: overlayPath,
        ),
      ),
    );
  }

  Future<void> _startCoaching() async {
    final status = await Permission.camera.status;

    if (!status.isGranted) {
      final result = await Permission.camera.request();
      if (result.isPermanentlyDenied) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Camera Permission Required'),
            content: const Text(
              'PoseCoach needs access to your camera for real-time pose guidance. '
              'Please enable camera access in system settings to use this feature.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
        return;
      }
      if (!result.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission is required to start coaching.')),
        );
        return;
      }
    }

    final refMap = await LocalStorageService.getSessionReference();

    if (mounted) {
      if (refMap == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Please upload a reference photo first!')),
        );
        _pickReferencePhoto();
        return;
      }

      final reference = ReferenceModel.fromMap(refMap);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LiveCoachScreen(reference: reference),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PoseCoach'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.backgroundColor,
              AppTheme.primaryColor.withValues(alpha: 0.05),
              AppTheme.backgroundColor,
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        size: 60, color: AppTheme.primaryColor),
                    const SizedBox(height: 24),
                    const Text(
                      'PoseCoach AI',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ready to capture perfection?',
                      style: TextStyle(
                          fontSize: 16,
                          color: AppTheme.textSecondary.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 48),

              _buildActionButton(
                context,
                title: 'Upload Reference',
                subtitle: 'Pick your target pose from gallery',
                icon: Icons.add_photo_alternate_rounded,
                onPressed: _pickReferencePhoto,
                isPrimary: true,
              ),

              const SizedBox(height: 20),

              _buildActionButton(
                context,
                title: 'Start Coaching',
                subtitle: 'Match your pose in real-time',
                icon: Icons.play_circle_fill_rounded,
                onPressed: _startCoaching,
                isPrimary: false,
              ),

              const SizedBox(height: 40),

              const Text(
                'Tip: Use a bright room for best AI accuracy',
                style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onPressed,
    required bool isPrimary,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isPrimary ? AppTheme.primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isPrimary
              ? null
              : Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
          boxShadow: [
            if (!isPrimary)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon,
                color: isPrimary ? Colors.white : AppTheme.primaryColor,
                size: 32),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isPrimary ? Colors.white : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          isPrimary ? Colors.white70 : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: isPrimary ? Colors.white60 : Colors.grey),
          ],
        ),
      ),
    );
  }
}
