import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/photo_quality_analyzer.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/camera_setting_pill.dart';
import '../../widgets/feedback_card.dart';

class CaptureReviewScreen extends StatefulWidget {
  final String imagePath;
  final Offset? nosePosition;

  const CaptureReviewScreen({
    super.key,
    required this.imagePath,
    this.nosePosition,
  });

  @override
  State<CaptureReviewScreen> createState() => _CaptureReviewScreenState();
}

class _CaptureReviewScreenState extends State<CaptureReviewScreen> {
  late Future<Map<String, dynamic>> _analysisFuture;

  @override
  void initState() {
    super.initState();
    _analysisFuture = PhotoQualityAnalyzer.analyze(
      widget.imagePath,
      nosePosition: widget.nosePosition,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Capture Analysis',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _analysisFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: AppTheme.primaryColor,
                    strokeWidth: 3,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Analyzing capture details...',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Text(
                'Analysis failed: ${snapshot.error ?? "No data"}',
                style: const TextStyle(color: AppTheme.errorColor),
              ),
            );
          }

          final data = snapshot.data!;
          final feedbackList = List<String>.from(data['feedback'] ?? []);

          final faceLum = double.tryParse(data['Face_Luminance'] ?? '0') ?? 0.0;
          final dofRatio = double.tryParse(data['Aperture_Depth_Ratio'] ?? '0') ?? 0.0;
          final dynRange = double.tryParse(data['Dynamic_Range_Width'] ?? '0') ?? 0.0;
          final colTemp = double.tryParse(data['Color_Temp_Index'] ?? '128') ?? 128.0;

          final iso = data['iso'].toString();
          final shutter = data['shutter'].toString();
          final wb = data['whiteBalance'].toString();
          final evVal = data['ev'] as double? ?? 0.0;
          final ev = (evVal >= 0 ? '+' : '') + evVal.toStringAsFixed(1);
          final source = data['source'] as String? ?? 'estimated';

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 260,
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.file(
                    File(widget.imagePath),
                    fit: BoxFit.cover,
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Coaching Metrics',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: source == 'merged'
                              ? AppTheme.successColor.withValues(alpha: 0.1)
                              : AppTheme.warningColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          source == 'merged' ? 'EXIF VERIFIED' : 'ESTIMATED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: source == 'merged' ? AppTheme.successColor : AppTheme.warningColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.45,
                    children: [
                      MetricCard(
                        title: 'Face Luminance',
                        value: faceLum.toStringAsFixed(1),
                        status: faceLum < ProThresholds.severeUnderExposed
                            ? 'Under-exposed'
                            : faceLum < ProThresholds.slightlyDark
                                ? 'Slightly dark'
                                : faceLum > ProThresholds.highlightClipping
                                    ? 'Over-exposed'
                                    : 'Balanced',
                        statusColor: faceLum < ProThresholds.slightlyDark || faceLum > ProThresholds.highlightClipping
                            ? (faceLum < ProThresholds.severeUnderExposed || faceLum > ProThresholds.highlightClipping ? AppTheme.errorColor : AppTheme.warningColor)
                            : AppTheme.successColor,
                        icon: Icons.face_rounded,
                      ),
                      MetricCard(
                        title: 'Depth of Field',
                        value: '${dofRatio.toStringAsFixed(1)}x',
                        status: dofRatio > ProThresholds.shallowPro
                            ? 'Shallow (Bokeh)'
                            : dofRatio < ProThresholds.deepLimit
                                ? 'Deep focus'
                                : 'Normal focus',
                        statusColor: dofRatio > ProThresholds.shallowPro
                            ? AppTheme.successColor
                            : dofRatio < ProThresholds.deepLimit
                                ? AppTheme.errorColor
                                : AppTheme.textSecondary,
                        icon: Icons.blur_on_rounded,
                      ),
                      MetricCard(
                        title: 'Dynamic Range',
                        value: dynRange.toStringAsFixed(0),
                        status: dynRange > ProThresholds.excellentHdr ? 'High' : 'Normal',
                        statusColor: dynRange > ProThresholds.excellentHdr ? AppTheme.successColor : AppTheme.textSecondary,
                        icon: Icons.hdr_strong_rounded,
                      ),
                      MetricCard(
                        title: 'Color Temperature',
                        value: colTemp.toStringAsFixed(1),
                        status: colTemp > ProThresholds.warmLimit
                            ? 'Warm / Yellow'
                            : colTemp < ProThresholds.coolLimit
                                ? 'Cool / Blue'
                                : 'Neutral',
                        statusColor: colTemp > ProThresholds.warmLimit || colTemp < ProThresholds.coolLimit
                            ? AppTheme.warningColor
                            : AppTheme.successColor,
                        icon: Icons.wb_sunny_rounded,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Optimal Camera Settings',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        CameraSettingPill(label: 'ISO', value: iso, icon: Icons.iso_rounded),
                        CameraSettingPill(label: 'Shutter', value: shutter, icon: Icons.shutter_speed_rounded),
                        CameraSettingPill(label: 'WB', value: wb, icon: Icons.wb_iridescent_rounded),
                        CameraSettingPill(label: 'EV', value: ev, icon: Icons.exposure_rounded),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Coach Critiques',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: feedbackList.map((critique) => FeedbackCard(critique: critique)).toList(),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: const Text('Save & Back to Home'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
