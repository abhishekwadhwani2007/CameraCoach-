import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../home/home_screen.dart';
import '../../widgets/permission_tile.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final Map<String, PermissionStatus> _permissionStatuses = {
    'camera': PermissionStatus.denied,
    'storage': PermissionStatus.denied,
    'sensors': PermissionStatus.denied,
  };

  bool get _allPermissionsGranted =>
      _permissionStatuses['camera']!.isGranted &&
      _permissionStatuses['storage']!.isGranted;

  @override
  void initState() {
    super.initState();
    _checkCurrentPermissions();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkCurrentPermissions() async {
    final camera = await Permission.camera.status;
    final storage = await _getStoragePermission().status;
    setState(() {
      _permissionStatuses['camera'] = camera;
      _permissionStatuses['storage'] = storage;
      _permissionStatuses['sensors'] = PermissionStatus.granted;
    });
  }

  Permission _getStoragePermission() {
    return Permission.photos;
  }

  Future<void> _requestAllPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final storageStatus = await _getStoragePermission().request();

    setState(() {
      _permissionStatuses['camera'] = cameraStatus;
      _permissionStatuses['storage'] = storageStatus;
      _permissionStatuses['sensors'] = PermissionStatus.granted;
    });
  }

  Future<void> _requestSinglePermission(String key) async {
    PermissionStatus status;
    if (key == 'camera') {
      status = await Permission.camera.request();
    } else if (key == 'storage') {
      status = await _getStoragePermission().request();
    } else {
      status = PermissionStatus.granted;
    }
    setState(() {
      _permissionStatuses[key] = status;
    });
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.onboardingDoneKey, true);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  void _nextPage() {
    if (_currentPage < AppConstants.totalOnboardingPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressBar(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => setState(() => _currentPage = index),
                children: [
                  _buildWelcomePage(),
                  _buildHowItWorksPage(),
                  _buildPermissionsPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: List.generate(AppConstants.totalOnboardingPages, (index) {
          return Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(
                  right: index < AppConstants.totalOnboardingPages - 1 ? 8 : 0),
              decoration: BoxDecoration(
                color: index <= _currentPage
                    ? AppTheme.primaryColor
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildWelcomePage() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.camera_alt_rounded,
              size: 100, color: AppTheme.primaryColor),
          const SizedBox(height: 32),
          Text('Welcome to PoseCoach',
              style: Theme.of(context).textTheme.headlineLarge,
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(
            'Your real-time AI coach that helps you match any pose perfectly for that perfect photo.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: _nextPage,
            child: const Text('Get Started'),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksPage() {
    final steps = [
      (
        '1',
        Icons.photo_library_rounded,
        'Upload a Reference Photo',
        'Choose any photo with the pose you want to replicate.'
      ),
      (
        '2',
        Icons.camera_rounded,
        'Enter Coach Mode',
        'Your camera guides you in real-time with pose overlays.'
      ),
      (
        '3',
        Icons.auto_awesome_rounded,
        'Auto-Capture at 97% Match',
        'When your pose matches, the app captures and enhances automatically.'
      ),
    ];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How It Works',
              style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 32),
          ...steps.map((step) => _buildStepRow(step.$2, step.$3, step.$4)),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: _nextPage,
            child: const Text('Next: Permissions'),
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primaryColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsPage() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text('Grant Permissions',
              style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 8),
          Text(
            'PoseCoach needs these permissions to guide your pose. All AI runs on-device — your data stays private.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 32),
          PermissionTile(
            icon: Icons.camera_alt_rounded,
            title: 'Camera',
            subtitle: 'Required for real-time pose detection and coaching.',
            status: _permissionStatuses['camera']!,
            onRequest: () => _requestSinglePermission('camera'),
          ),
          const SizedBox(height: 12),
          PermissionTile(
            icon: Icons.photo_library_rounded,
            title: 'Photo Library',
            subtitle: 'To upload reference photos and save captured images.',
            status: _permissionStatuses['storage']!,
            onRequest: () => _requestSinglePermission('storage'),
          ),
          const SizedBox(height: 12),
          const PermissionTile(
            icon: Icons.sensors_rounded,
            title: 'Motion & Sensors',
            subtitle: 'Device orientation for accurate angle guidance.',
            status: PermissionStatus.granted,
            onRequest: null,
          ),
          const Spacer(),
          if (!_allPermissionsGranted) ...[
            ElevatedButton(
              onPressed: _requestAllPermissions,
              child: const Text('Grant All Permissions'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _completeOnboarding,
              child: Text(
                'Skip for now (some features limited)',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
          ] else ...[
            ElevatedButton(
              onPressed: _completeOnboarding,
              child: const Text('Start Coaching →'),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
