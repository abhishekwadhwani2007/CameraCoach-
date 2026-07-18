import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'camera_ui_colors.dart';
import 'manual_controls_panel.dart';

class BottomBar extends StatelessWidget {
  final int selectedModeIndex;
  final ValueChanged<int> onModeChanged;
  final double zoom;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onCapture;
  final bool capturing;
  final VoidCallback onFlip;
  final AnimationController flipAnim;
  final double bottomSafeAreaPadding;
  final double matchScore;
  final String guidance;
  final String iso;
  final String shutter;
  final String wb;
  final double ev;
  final String manualFocusValue;

  const BottomBar({
    super.key,
    required this.selectedModeIndex,
    required this.onModeChanged,
    required this.zoom,
    required this.onZoomChanged,
    required this.onCapture,
    required this.capturing,
    required this.onFlip,
    required this.flipAnim,
    required this.bottomSafeAreaPadding,
    required this.matchScore,
    required this.guidance,
    required this.iso,
    required this.shutter,
    required this.wb,
    required this.ev,
    required this.manualFocusValue,
  });

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.transparent,
        padding: EdgeInsets.only(bottom: bottomSafeAreaPadding + 8, top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectedModeIndex == 1) ...[
              ManualControlsRow(
                iso: iso,
                shutter: shutter,
                wb: wb,
                ev: ev,
                mf: manualFocusValue,
              ),
              const SizedBox(height: 8),
            ],
            ZoomSelector(
              currentZoom: zoom,
              onZoomChanged: onZoomChanged,
              matchScore: matchScore,
              guidance: guidance,
            ),
            const SizedBox(height: 10),
            ModeTabs(selected: selectedModeIndex, onSelect: onModeChanged),
            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cameraBorderColor),
                    ),
                    child: const Icon(Icons.image_outlined,
                        color: Colors.white38, size: 24),
                  ),

                  ShutterBtn(onTap: onCapture, busy: capturing, matchScore: matchScore),

                  AnimatedBuilder(
                    animation: flipAnim,
                    builder: (_, child) => Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.rotationY(flipAnim.value * 3.14159),
                      child: child,
                    ),
                    child: GestureDetector(
                      onTap: onFlip,
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          shape: BoxShape.circle,
                          border: Border.all(color: cameraBorderColor),
                        ),
                        child: const Icon(Icons.flip_camera_ios_outlined,
                            color: cameraTextColor, size: 24),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class ZoomSelector extends StatelessWidget {
  final double currentZoom;
  final ValueChanged<double> onZoomChanged;
  final double matchScore;
  final String guidance;

  const ZoomSelector({
    super.key,
    required this.currentZoom,
    required this.onZoomChanged,
    required this.matchScore,
    required this.guidance,
  });

  @override
  Widget build(BuildContext context) {
    final presets = [1.0, 2.0, 4.0];
    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: presets.map((z) {
            final active = (currentZoom - z).abs() < 0.15;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onZoomChanged(z);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? Colors.black87 : Colors.black45,
                  border: Border.all(
                    color: active ? cameraAccentGold : Colors.white24,
                    width: active ? 1.5 : 1.0,
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: cameraAccentGold.withValues(alpha: 0.15),
                            blurRadius: 4,
                            spreadRadius: 0.5,
                          )
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${z.toInt()}x',
                  style: TextStyle(
                    color: active ? cameraAccentGold : Colors.white70,
                    fontSize: 10,
                    fontWeight: active ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        Positioned(
          left: 28,
          child: IgnorePointer(
            child: Text(
              'Match: ${matchScore.toInt()}%',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (guidance != 'Hold it right there' && matchScore < 95)
          Positioned(
            right: 28,
            child: IgnorePointer(
              child: SizedBox(
                width: 150,
                child: Text(
                  guidance,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ModeTabs extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  static const _modes = ['PHOTO', 'PRO', 'VIDEO'];

  const ModeTabs({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_modes.length, (i) {
          final on = i == selected;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _modes[i],
                    style: TextStyle(
                      color: on ? cameraAccentGold : Colors.white38,
                      fontSize: 12,
                      fontWeight: on ? FontWeight.w800 : FontWeight.w400,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: on ? 22 : 0,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: cameraAccentGold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      );
}

class ShutterBtn extends StatefulWidget {
  final VoidCallback onTap;
  final bool busy;
  final double matchScore;

  const ShutterBtn({
    super.key,
    required this.onTap,
    required this.busy,
    required this.matchScore,
  });

  @override
  State<ShutterBtn> createState() => _ShutterBtnState();
}

class _ShutterBtnState extends State<ShutterBtn>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressAnimController;
  late Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pressAnimController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 120),
        lowerBound: 0.88,
        upperBound: 1.0,
        value: 1.0);
    _pressScale = _pressAnimController;
  }

  @override
  void dispose() {
    _pressAnimController.dispose();
    super.dispose();
  }

  Future<void> _press() async {
    await _pressAnimController.reverse();
    await _pressAnimController.forward();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: _press,
        child: ScaleTransition(
          scale: _pressScale,
          child: SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white60, width: 2.5),
                  ),
                ),
                Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: widget.busy
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(
                              color: Colors.black87, strokeWidth: 2),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      );
}
