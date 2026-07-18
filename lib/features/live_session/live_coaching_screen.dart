import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../core/constants.dart';
import '../../utils/logger.dart';
import '../review/capture_review_screen.dart';
import '../../models/reference_model.dart';
import '../../services/hardware_camera_controls.dart';
import '../../services/pose_comparison_service.dart';
import '../../services/pose_service.dart';
import 'widgets/viewfinder.dart';
import 'widgets/top_bar.dart';
import 'widgets/bottom_bar.dart';

class LiveCoachScreen extends StatefulWidget {
  final ReferenceModel reference;
  const LiveCoachScreen({super.key, required this.reference});

  @override
  State<LiveCoachScreen> createState() => _LiveCoachScreenState();
}

class _LiveCoachScreenState extends State<LiveCoachScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraReady = false;
  bool _isCapturing = false;
  bool _isFlashAnimating = false;
  bool _isFrontCamera = false;
  bool _isGridVisible = true;
  Map<String, dynamic>? _referenceLandmarks;
  Size? _referenceImageSize;
  String? _referenceOutlinePath;
  double _poseMatchPercent = 0;
  double _smoothedMatchPercent = 0;
  DateTime? _lastGuidanceUpdateTime;
  String _coachingGuidanceText = 'Finding pose...';
  int _processedFrameCount = 0;
  int _stableMatchFrames = 0;
  bool _isPoseProcessing = false;
  bool _poseStreamActive = false;
  Offset? _lastNosePosition;

  bool _isAutoCapturing = false;
  int _countdownSeconds = 3;
  Timer? _autoCaptureTimer;

  Offset? _focusTapPoint;
  late AnimationController _focusAnimController;
  late Animation<double> _focusScale;
  late Animation<double> _focusOpacity;

  int _selectedModeIndex = 1;

  int _selectedIsoIndex = 2;
  int _selectedShutterIndex = 3;
  int _selectedWhiteBalanceIndex = 0;
  double _exposureCompensation = 0.0;

  static const _isoOptions = ['50', '100', '200', '400', '800'];
  static const _shutterSpeedOptions = [
    '1/4000',
    '1/2000',
    '1/1000',
    '1/500',
    '1/125',
    '1/60',
    '1/15',
    '1s',
    '4s',
    '8s',
    '30s',
  ];
  static const _whiteBalanceOptions = ['AWB', '2300K', '3200K', '5500K', '6500K', '8000K'];

  SensorRanges? _sensorRanges;

  // ignore: prefer_final_fields
  double _manualFocusDistance = 0.5;

  final bool _isFocusPeakingEnabled = false;
  StreamSubscription<CameraImage>? _focusPeakingSubscription;
  final List<Offset> _focusPeakingEdgePoints = [];

  bool get _isLongExposure =>
      _shutterSpeedOptions[_selectedShutterIndex].endsWith('s') &&
      !_shutterSpeedOptions[_selectedShutterIndex].contains('/');

  double _currentZoomLevel = 1.0;
  double _pinchStartZoomLevel = 1.0;

  final int _selectedAspectRatioIndex = 0;
  static const _aspectRatioValues = [3 / 4, 9 / 16, 1.0, null];

  FlashMode _flashMode = FlashMode.off;
  final int _selfTimerSeconds = 0;
  final int _selectedResolutionIndex = 1;
  static const _resolutionPresets = [
    ResolutionPreset.low,
    ResolutionPreset.high,
    ResolutionPreset.veryHigh
  ];

  late AnimationController _flipAnimController;
  Timer? _timerCountdown;

  int? _exposureCountdown;
  Timer? _exposureTimer;

  @override
  void initState() {
    super.initState();

    _focusAnimController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _focusScale = Tween(begin: 1.4, end: 1.0)
        .animate(CurvedAnimation(parent: _focusAnimController, curve: Curves.easeOut));
    _focusOpacity = Tween(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _focusAnimController, curve: const Interval(0.6, 1.0)));

    _flipAnimController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));

    _loadReferenceMetadata();
    _initCamera();
  }

  void _loadReferenceMetadata() {
    _referenceOutlinePath = widget.reference.outlinePath;
    final keypoints = widget.reference.keypointsJson;
    if (keypoints != null && keypoints.isNotEmpty) {
      try {
        final decoded = jsonDecode(keypoints);
        if (decoded is Map<String, dynamic>) {
          _referenceLandmarks = decoded;
          final w = widget.reference.width;
          final h = widget.reference.height;
          if (w != null && h != null && w > 0 && h > 0) {
            _referenceImageSize = Size(w, h);
          }
        } else {
          AppLogger.error('Corrupt keypointsJson: unexpected type ${decoded.runtimeType}');
        }
      } catch (e) {
        AppLogger.error('Reference keypoints parse: $e');
      }
    }

    final raw = widget.reference.proSettingsJson;
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final map = decoded;

      final isoIdx = _isoOptions.indexOf('${map['iso'] ?? ''}');
      final shutterIdx = _shutterSpeedOptions.indexOf('${map['shutter'] ?? ''}');
      final wbIdx = _whiteBalanceOptions.indexOf('${map['whiteBalance'] ?? ''}');
      if (isoIdx >= 0) _selectedIsoIndex = isoIdx;
      if (shutterIdx >= 0) _selectedShutterIndex = shutterIdx;
      if (wbIdx >= 0) _selectedWhiteBalanceIndex = wbIdx;

      final evRaw = map['ev'];
      if (evRaw is num) {
        _exposureCompensation = evRaw.toDouble().clamp(-3.0, 3.0);
      }
    } catch (e) {
      AppLogger.error('Reference pro preset parse: $e');
    }
  }

  @override
  void dispose() {
    _timerCountdown?.cancel();
    _exposureTimer?.cancel();
    _autoCaptureTimer?.cancel();
    _focusPeakingSubscription?.cancel();
    _stopPoseCoachingStream();
    _cameraController?.dispose();
    PoseService.dispose();
    _focusAnimController.dispose();
    _flipAnimController.dispose();
    super.dispose();
  }

  Future<void> _initCamera({bool front = false}) async {
    try {
      await _stopPoseCoachingStream();
      final cams = await availableCameras();
      _cameras = cams;
      if (cams.isEmpty) return;

      final pick = cams.firstWhere(
        (c) =>
            c.lensDirection ==
            (front ? CameraLensDirection.front : CameraLensDirection.back),
        orElse: () => cams.first,
      );

      final nc = CameraController(pick, _resolutionPresets[_selectedResolutionIndex],
          enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
      await nc.initialize();

      if (!mounted) {
        await nc.dispose();
        return;
      }

      final old = _cameraController;
      _cameraController = nc;
      await old?.dispose();

      try {
        await nc.setFlashMode(_flashMode);
      } catch (_) {}

      setState(() {
        _isCameraReady = true;
        _isFrontCamera = front;
        _currentZoomLevel = 1.0;
      });

      final ranges = await HardwareCameraControls.getSensorRanges();
      if (mounted) {
        setState(() => _sensorRanges = ranges);
      }

      if (_selectedModeIndex == 1) {
        await _applyProSettings();
      }
      await _startPoseCoachingStream();
    } catch (e) {
      AppLogger.error('Camera init: $e');
    }
  }

  Future<void> _applyProSettings() async {
    if (_sensorRanges == null || _cameraController == null || !_isCameraReady) return;
    final iso = int.tryParse(_isoOptions[_selectedIsoIndex]) ?? 200;
    await HardwareCameraControls.setManualExposure(
      iso: iso,
      shutterLabel: _shutterSpeedOptions[_selectedShutterIndex],
      ranges: _sensorRanges!,
    );
    await HardwareCameraControls.setWhiteBalance(wbLabel: _whiteBalanceOptions[_selectedWhiteBalanceIndex]);
    await _applyEv(_exposureCompensation);
  }

  Future<void> _startPoseCoachingStream() async {
    if (_poseStreamActive || _isFocusPeakingEnabled || _referenceLandmarks == null) {
      return;
    }
    final controller = _cameraController;
    if (controller == null || !_isCameraReady || controller.value.isStreamingImages) {
      return;
    }
    try {
      await controller.startImageStream(_handlePoseFrame);
      _poseStreamActive = true;
    } catch (e) {
      AppLogger.error('Pose stream start: $e');
    }
  }

  Future<void> _stopPoseCoachingStream() async {
    if (!_poseStreamActive) return;
    try {
      await _cameraController?.stopImageStream();
    } catch (_) {}
    _poseStreamActive = false;
    _isPoseProcessing = false;
  }

  void _cancelAutoCapture() {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    if (mounted) setState(() => _isAutoCapturing = false);
    _startPoseCoachingStream();
  }

  void _startAutoCapture() {
    if (_isAutoCapturing) return;
    _stopPoseCoachingStream();
    if (mounted) {
      setState(() {
        _isAutoCapturing = true;
        _countdownSeconds = 3;
      });
    }
    _autoCaptureTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _countdownSeconds--);  
      if (_countdownSeconds <= 0) {
        timer.cancel();
        _cancelAutoCapture();
        _capture();
      }
    });
  }

  Future<void> _handlePoseFrame(CameraImage image) async {
    if (_isPoseProcessing ||
        _isCapturing ||
        _referenceLandmarks == null ||
        _cameraController == null) {
      return;
    }
    _processedFrameCount++;
    if (_processedFrameCount % AppConstants.frameSkip != 0) return;

    _isPoseProcessing = true;
    try {
      final poses = await PoseService.detectPoseFromCameraImage(
        image: image,
        sensorOrientation: _cameraController!.description.sensorOrientation,
      );
      if (!mounted || poses.isEmpty) {
        if (mounted) {
          setState(() {
            _poseMatchPercent = 0;
            _smoothedMatchPercent = 0;
            _coachingGuidanceText = 'Stand in frame';
            _stableMatchFrames = 0;
            _lastNosePosition = null;
          });
        }
        return;
      }

      final live = PoseService.poseToMap(_selectMainPose(poses));
      final nose = live['nose'];
      if (nose != null) {
        _lastNosePosition = Offset(
          (nose['x'] as num).toDouble(),
          (nose['y'] as num).toDouble(),
        );
      } else {
        _lastNosePosition = null;
      }

      final result = PoseComparisonService.evaluate(
        live,
        _referenceLandmarks!,
        mirrorLive: _isFrontCamera,
      );

      const double emaAlpha = 0.3;
      final newSmoothed = (emaAlpha * result.score) + ((1 - emaAlpha) * _smoothedMatchPercent);

      final pass = result.isReliable && newSmoothed >= 97.0;

      final now = DateTime.now();
      final String newGuidance = result.feedback.isEmpty
          ? 'Hold it right there!'
          : result.feedback.first;
      final bool feedbackCooledDown = _lastGuidanceUpdateTime == null ||
          now.difference(_lastGuidanceUpdateTime!).inMilliseconds >= 1500;
      final bool guidanceChanged = newGuidance != _coachingGuidanceText;

      if (mounted) {
        setState(() {
          _smoothedMatchPercent = newSmoothed;
          _poseMatchPercent = newSmoothed;
          if (guidanceChanged && feedbackCooledDown) {
            _coachingGuidanceText = newGuidance;
            _lastGuidanceUpdateTime = now;
          }
          _stableMatchFrames = pass ? _stableMatchFrames + 1 : 0;
        });
      }

      if (_stableMatchFrames >= 5 && !_isCapturing && !_isAutoCapturing) {
        _startAutoCapture();
      }
    } catch (e) {
      AppLogger.error('Pose frame: $e');
    } finally {
      _isPoseProcessing = false;
    }
  }

  Pose _selectMainPose(List<Pose> poses) {
    if (poses.length == 1) return poses.first;
    poses.sort((a, b) => _poseArea(b).compareTo(_poseArea(a)));
    return poses.first;
  }

  double _poseArea(Pose pose) {
    final points = pose.landmarks.values;
    if (points.isEmpty) return 0;
    final xs = points.map<double>((p) => p.x).toList();
    final ys = points.map<double>((p) => p.y).toList();
    return (xs.reduce(max) - xs.reduce(min)) *
        (ys.reduce(max) - ys.reduce(min));
  }

  Future<void> _onTap(TapDownDetails d) async {
    if (_cameraController == null || !_isCameraReady) return;
    final s = MediaQuery.of(context).size;
    setState(() => _focusTapPoint = d.localPosition);
    _focusAnimController.forward(from: 0);

    try {
      await _cameraController!.setFocusPoint(
          Offset(d.localPosition.dx / s.width, d.localPosition.dy / s.height));
      await _cameraController!.setExposurePoint(
          Offset(d.localPosition.dx / s.width, d.localPosition.dy / s.height));
    } catch (_) {}

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _focusTapPoint = null);
  }

  void _scaleStart(ScaleStartDetails d) => _pinchStartZoomLevel = _currentZoomLevel;
  Future<void> _scaleUpdate(ScaleUpdateDetails d) async {
    final z = (_pinchStartZoomLevel * d.scale).clamp(1.0, 8.0);
    setState(() => _currentZoomLevel = z);
    try {
      await _cameraController?.setZoomLevel(z);
    } catch (_) {}
  }

  Future<void> _applyEv(double v) async {
    setState(() => _exposureCompensation = v);
    if (_cameraController == null || !_isCameraReady) return;
    try {
      final minEv = await _cameraController!.getMinExposureOffset();
      final maxEv = await _cameraController!.getMaxExposureOffset();
      final clamped = v.clamp(minEv, maxEv);
      await _cameraController!.setExposureOffset(clamped);
    } catch (_) {}
  }

  Future<void> _captureWithTimer() async {
    if (_isCapturing || !_isCameraReady) return;
    if (_selfTimerSeconds == 0) {
      _capture();
      return;
    }

    int remaining = _selfTimerSeconds;
    setState(() => _isCapturing = true);

    _timerCountdown = Timer.periodic(const Duration(seconds: 1), (t) {
      remaining--;
      if (remaining <= 0) {
        t.cancel();
        setState(() => _isCapturing = false);
        _capture();
      } else {
        HapticFeedback.lightImpact();
        setState(() {});
      }
    });
  }

  Future<void> _flip() async {
    if (_cameras == null || _cameras!.length < 2) return;
    HapticFeedback.lightImpact();
    await _stopPoseCoachingStream();
    await _flipAnimController.forward();
    if (mounted) setState(() => _isCameraReady = false);

    final lensDirection = _cameraController?.description.lensDirection;
    final newCamera = _cameras!.firstWhere(
      (c) => c.lensDirection != lensDirection,
      orElse: () => _cameras!.first,
    );
    if (_cameraController != null) {
      await _cameraController!.dispose();
    }
    _cameraController = CameraController(
      newCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    try {
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraReady = true;
        _isFrontCamera = newCamera.lensDirection == CameraLensDirection.front;
        _currentZoomLevel = 1.0;
      });
      await _startPoseCoachingStream();
    } catch (e) {
      debugPrint('Camera flip error: $e');
    } finally {
      _flipAnimController.reverse();
    }
  }

  Future<void> _capture() async {
    if (_isCapturing || !_isCameraReady) return;
    HapticFeedback.mediumImpact();
    await _stopPoseCoachingStream();

    setState(() {
      _isCapturing = true;
      _isFlashAnimating = true;
    });
    await Future.delayed(const Duration(milliseconds: 70));
    setState(() => _isFlashAnimating = false);

    if (_isLongExposure && _selectedModeIndex == 1) {
      final secs = _longExposureSecs(_shutterSpeedOptions[_selectedShutterIndex]);
      if (secs > 1) {
        setState(() => _exposureCountdown = secs);
        _exposureTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) {
            t.cancel();
            return;
          }
          final remaining = (_exposureCountdown ?? 0) - 1;
          setState(
              () => _exposureCountdown = remaining <= 0 ? null : remaining);
          if (remaining <= 0) t.cancel();
        });
      }
    }

    try {
      final photo = await _cameraController!.takePicture();

      _exposureTimer?.cancel();
      if (mounted) setState(() => _exposureCountdown = null);

      try {
        await Gal.putImage(photo.path);
      } catch (galError) {
        AppLogger.error('Gallery save failed: $galError');
      }

      if (!mounted) return;
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CaptureReviewScreen(
              imagePath: photo.path,
              nosePosition: _lastNosePosition,
            ),
          ));
    } catch (e) {
      AppLogger.error('Capture: $e');
      _exposureTimer?.cancel();
      setState(() {
        _isCapturing = false;
        _exposureCountdown = null;
      });
      await _startPoseCoachingStream();
    }
  }

  int _longExposureSecs(String label) {
    if (label == '1s') return 1;
    if (label == '4s') return 4;
    if (label == '8s') return 8;
    if (label == '30s') return 30;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final aspect = _aspectRatioValues[_selectedAspectRatioIndex];
    final bool isFramed = aspect == 0.75 || aspect == 1.0;

    final viewfinderWidget = Viewfinder(
      controller: _cameraController,
      ready: _isCameraReady,
      focusTapPoint: _focusTapPoint,
      focusAnimController: _focusAnimController,
      focusScale: _focusScale,
      focusOpacity: _focusOpacity,
      showGrid: _isGridVisible,
      showFlash: _isFlashAnimating,
      zoom: _currentZoomLevel,
      ratioAspect: aspect,
      onTap: _onTap,
      onScaleStart: _scaleStart,
      onScaleUpdate: _scaleUpdate,
      showPeaking: _isFocusPeakingEnabled,
      peakingEdges: _focusPeakingEdgePoints,
      isLongExposure: _isLongExposure && _selectedModeIndex == 1,
      exposureCountdown: _exposureCountdown,
      ghostImagePath: null,
      referenceLandmarks: _referenceLandmarks,
      referenceImageSize: _referenceImageSize,
      referenceOutlinePath: _referenceOutlinePath,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,

        body: Stack(
          children: [
            if (isFramed)
              Positioned(
                top: mq.padding.top + 56,
                left: 0,
                right: 0,
                child: AspectRatio(
                  aspectRatio: aspect!,
                  child: viewfinderWidget,
                ),
              )
            else
              Positioned.fill(child: viewfinderWidget),
            Positioned(
              top: mq.padding.top + 8,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TopBarControlButton(
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.pop(context),
                  ),
                  Row(
                    children: [
                      TopBarControlButton(
                        icon: _flashMode == FlashMode.off
                            ? Icons.flash_off_rounded
                            : Icons.flash_on_rounded,
                        active: _flashMode != FlashMode.off,
                        onPressed: () {
                          setState(() {
                            _flashMode = _flashMode == FlashMode.off
                                ? FlashMode.auto
                                : FlashMode.off;
                          });
                          _cameraController?.setFlashMode(_flashMode);
                        },
                      ),
                      const SizedBox(width: 10),
                      TopBarControlButton(
                        icon: Icons.grid_3x3_rounded,
                        active: _isGridVisible,
                        onPressed: () => setState(() => _isGridVisible = !_isGridVisible),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BottomBar(
                selectedModeIndex: _selectedModeIndex,
                onModeChanged: (i) => setState(() => _selectedModeIndex = i),
                zoom: _currentZoomLevel,
                onZoomChanged: (z) async {
                  setState(() => _currentZoomLevel = z);
                  try {
                    await _cameraController?.setZoomLevel(z);
                  } catch (_) {}
                },
                onCapture: _captureWithTimer,
                capturing: _isCapturing,
                onFlip: _flip,
                flipAnim: _flipAnimController,
                bottomSafeAreaPadding: mq.padding.bottom,
                matchScore: _poseMatchPercent,
                guidance: _coachingGuidanceText,
                iso: _isoOptions[_selectedIsoIndex],
                shutter: _shutterSpeedOptions[_selectedShutterIndex],
                wb: _whiteBalanceOptions[_selectedWhiteBalanceIndex],
                ev: _exposureCompensation,
                manualFocusValue: _manualFocusDistance == 0.0
                    ? 'Near'
                    : _manualFocusDistance == 1.0
                        ? 'Far'
                        : _manualFocusDistance.toStringAsFixed(1),
              ),
            ),

            if (_isAutoCapturing)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$_countdownSeconds',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 120,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: Colors.black87,
                              blurRadius: 20,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Perfect pose! Hold still...',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: _cancelAutoCapture,
                        icon: const Icon(Icons.cancel_rounded),
                        label: const Text('Cancel'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 36,
                            vertical: 16,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
