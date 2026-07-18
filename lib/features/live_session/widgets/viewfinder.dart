import 'dart:io';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'camera_ui_colors.dart';

class Viewfinder extends StatelessWidget {
  final CameraController? controller;
  final bool ready;
  final Offset? focusTapPoint;
  final AnimationController focusAnimController;
  final Animation<double> focusScale;
  final Animation<double> focusOpacity;
  final bool showGrid;
  final bool showFlash;
  final double zoom;
  final double? ratioAspect;
  final void Function(TapDownDetails) onTap;
  final void Function(ScaleStartDetails) onScaleStart;
  final void Function(ScaleUpdateDetails) onScaleUpdate;
  final bool showPeaking;
  final List<Offset> peakingEdges;
  final bool isLongExposure;
  final int? exposureCountdown;
  final String? ghostImagePath;
  final Map<String, dynamic>? referenceLandmarks;
  final Size? referenceImageSize;
  final String? referenceOutlinePath;

  const Viewfinder({
    super.key,
    required this.controller,
    required this.ready,
    required this.focusTapPoint,
    required this.focusAnimController,
    required this.focusScale,
    required this.focusOpacity,
    required this.showGrid,
    required this.showFlash,
    required this.zoom,
    required this.ratioAspect,
    required this.onTap,
    required this.onScaleStart,
    required this.onScaleUpdate,
    this.showPeaking = false,
    this.peakingEdges = const [],
    this.isLongExposure = false,
    this.exposureCountdown,
    this.ghostImagePath,
    this.referenceLandmarks,
    this.referenceImageSize,
    this.referenceOutlinePath,
  });

  @override
  Widget build(BuildContext context) {
    final overlayFile = referenceOutlinePath == null || referenceOutlinePath!.isEmpty
        ? null
        : File(referenceOutlinePath!);

    return ClipRect(
      child: GestureDetector(
        onTapDown: onTap,
        onScaleStart: onScaleStart,
        onScaleUpdate: onScaleUpdate,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready && controller != null)
              SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 100,
                    height: 100 * controller!.value.aspectRatio,
                    child: CameraPreview(controller!),
                  ),
                ),
              )
            else
              const ColoredBox(
                color: Colors.black,
                child: Center(
                  child: CircularProgressIndicator(
                    color: cameraAccentGold,
                    strokeWidth: 2,
                  ),
                ),
              ),
            if (ghostImagePath != null)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.35,
                  child: Image.file(File(ghostImagePath!), fit: BoxFit.cover),
                ),
              ),
            const Vignette(),
            if (showGrid) const GridOverlay(),
            if (referenceLandmarks != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: overlayFile != null && overlayFile.existsSync()
                      ? Image.file(
                          overlayFile,
                          key: ValueKey(referenceOutlinePath),
                          fit: BoxFit.contain,
                        )
                      : referenceOutlinePath == null
                          ? Image.asset(
                              'assets/images/transparent_silhouette.png',
                              fit: BoxFit.contain,
                            )
                          : const SizedBox.shrink(),
                ),
              ),
            if (showPeaking && peakingEdges.isNotEmpty)
              Positioned.fill(
                child: CustomPaint(painter: FocusPeakingPainter(peakingEdges)),
              ),
            if (ratioAspect != null) const CornerMarkers(),
            if (exposureCountdown != null)
              Positioned.fill(
                child: Container(
                  color: Colors.black38,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${exposureCountdown}s',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 64,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        const Text(
                          'Exposing...',
                          style: TextStyle(color: Colors.white60, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (zoom > 1.01)
              Positioned(
                top: 14,
                left: 0,
                right: 0,
                child: Center(child: ZoomBadge(zoom: zoom)),
              ),
            if (focusTapPoint != null)
              AnimatedBuilder(
                animation: focusAnimController,
                builder: (_, __) => Positioned(
                  left: focusTapPoint!.dx - 34,
                  top: focusTapPoint!.dy - 34,
                  child: Opacity(
                    opacity: 1 - focusOpacity.value,
                    child: Transform.scale(
                      scale: focusScale.value,
                      child: SizedBox(
                        width: 68,
                        height: 68,
                        child: CustomPaint(painter: FocusRingPainter()),
                      ),
                    ),
                  ),
                ),
              ),
            if (showFlash) Positioned.fill(child: Container(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class FocusPeakingPainter extends CustomPainter {
  final List<Offset> edges;
  FocusPeakingPainter(this.edges);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00FF41)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.fill;
    for (final e in edges) {
      canvas.drawCircle(e, 1.2, paint);
    }
  }

  @override
  bool shouldRepaint(FocusPeakingPainter old) => old.edges != edges;
}

class Vignette extends StatelessWidget {
  const Vignette({super.key});

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.1,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.55)
              ],
              stops: const [0.6, 1.0],
            ),
          ),
        ),
      );
}

class GridOverlay extends StatelessWidget {
  const GridOverlay({super.key});

  @override
  Widget build(BuildContext context) => SizedBox.expand(
        child: CustomPaint(painter: GridPainter()),
      );
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 0.9;

    for (int i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class CornerMarkers extends StatelessWidget {
  const CornerMarkers({super.key});

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: CustomPaint(painter: CornerPainter()),
      );
}

class CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const len = 20.0;
    const margin = 0.0;

    canvas.drawLine(
        const Offset(margin, margin), const Offset(margin + len, margin), p);
    canvas.drawLine(
        const Offset(margin, margin), const Offset(margin, margin + len), p);
    canvas.drawLine(Offset(size.width - margin, margin),
        Offset(size.width - margin - len, margin), p);
    canvas.drawLine(Offset(size.width - margin, margin),
        Offset(size.width - margin, margin + len), p);
    canvas.drawLine(Offset(margin, size.height - margin),
        Offset(margin + len, size.height - margin), p);
    canvas.drawLine(Offset(margin, size.height - margin),
        Offset(margin, size.height - margin - len), p);
    canvas.drawLine(Offset(size.width - margin, size.height - margin),
        Offset(size.width - margin - len, size.height - margin), p);
    canvas.drawLine(Offset(size.width - margin, size.height - margin),
        Offset(size.width - margin, size.height - margin - len), p);
  }

  @override
  bool shouldRepaint(_) => false;
}

class FocusRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = cameraAccentGold
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    const cut = 14.0;
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(cut, 0)
      ..lineTo(w - cut, 0)
      ..moveTo(w, cut)
      ..lineTo(w, h - cut)
      ..moveTo(w - cut, h)
      ..lineTo(cut, h)
      ..moveTo(0, h - cut)
      ..lineTo(0, cut);

    canvas.drawPath(path, p);

    canvas.drawLine(const Offset(0, 0), const Offset(cut, 0), p);
    canvas.drawLine(const Offset(0, 0), const Offset(0, cut), p);
    canvas.drawLine(Offset(w, 0), Offset(w - cut, 0), p);
    canvas.drawLine(Offset(w, 0), Offset(w, cut), p);
    canvas.drawLine(Offset(0, h), Offset(cut, h), p);
    canvas.drawLine(Offset(0, h), Offset(0, h - cut), p);
    canvas.drawLine(Offset(w, h), Offset(w - cut, h), p);
    canvas.drawLine(Offset(w, h), Offset(w, h - cut), p);
  }

  @override
  bool shouldRepaint(_) => false;
}

class ZoomBadge extends StatelessWidget {
  final double zoom;
  const ZoomBadge({super.key, required this.zoom});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: cameraAccentGold.withValues(alpha: 0.8), width: 1),
            ),
            child: Text(
              '${zoom.toStringAsFixed(1)}×',
              style: const TextStyle(
                  color: cameraAccentGold,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5),
            ),
          ),
        ),
      );
}
