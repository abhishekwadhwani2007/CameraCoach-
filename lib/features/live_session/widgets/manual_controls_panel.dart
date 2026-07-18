import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'camera_ui_colors.dart';

class ManualControlsPanel extends StatelessWidget {
  final int selectedIsoIndex;
  final List<String> isoOptions;
  final int selectedShutterIndex;
  final List<String> shutterSpeedOptions;
  final int selectedWbIndex;
  final List<String> whiteBalanceOptions;
  final double ev;
  final int selectedMeteringIndex;
  final List<String> focusDistanceOptions;
  final int selectedFocusIndex;
  final String? expanded;
  final void Function(String) onToggle;
  final ValueChanged<int> onIso;
  final ValueChanged<int> onShutter;
  final ValueChanged<int> onWb;
  final ValueChanged<double> onEv;
  final ValueChanged<int> onMf;
  final ValueChanged<int> onMetering;

  const ManualControlsPanel({
    super.key,
    required this.selectedIsoIndex,
    required this.isoOptions,
    required this.selectedShutterIndex,
    required this.shutterSpeedOptions,
    required this.selectedWbIndex,
    required this.whiteBalanceOptions,
    required this.ev,
    required this.selectedMeteringIndex,
    required this.focusDistanceOptions,
    required this.selectedFocusIndex,
    required this.expanded,
    required this.onToggle,
    required this.onIso,
    required this.onShutter,
    required this.onWb,
    required this.onEv,
    required this.onMf,
    required this.onMetering,
  });

  static const _meteringModes = ['Matrix', 'Center', 'Spot'];

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                ControlChip(
                    label: 'ISO',
                    value: isoOptions[selectedIsoIndex],
                    active: expanded == 'ISO',
                    onTap: () => onToggle('ISO')),
                const SizedBox(width: 8),
                ControlChip(
                    label: 'SS',
                    value: shutterSpeedOptions[selectedShutterIndex],
                    active: expanded == 'SS',
                    onTap: () => onToggle('SS')),
                const SizedBox(width: 8),
                ControlChip(
                    label: 'WB',
                    value: whiteBalanceOptions[selectedWbIndex],
                    active: expanded == 'WB',
                    onTap: () => onToggle('WB')),
                const SizedBox(width: 8),
                ControlChip(
                  label: 'EV',
                  value: ev >= 0
                      ? '+${ev.toStringAsFixed(1)}'
                      : ev.toStringAsFixed(1),
                  active: expanded == 'EV',
                  onTap: () => onToggle('EV'),
                ),
                const SizedBox(width: 8),
                ControlChip(
                  label: 'MF',
                  value: focusDistanceOptions[selectedFocusIndex],
                  active: expanded == 'MF',
                  onTap: () => onToggle('MF'),
                ),
                const SizedBox(width: 8),
                ControlChip(
                  label: 'MTR',
                  value: _meteringModes[selectedMeteringIndex],
                  active: expanded == 'MTR',
                  onTap: () => onToggle('MTR'),
                ),
              ]),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: expanded == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _buildPicker(),
                    ),
            ),
          ],
        ),
      );

  Widget _buildPicker() {
    switch (expanded) {
      case 'ISO':
        return ControlValuePicker(items: isoOptions, selectedIndex: selectedIsoIndex, onChanged: onIso);
      case 'SS':
        return ControlValuePicker(
            items: shutterSpeedOptions, selectedIndex: selectedShutterIndex, onChanged: onShutter);
      case 'WB':
        return ControlValuePicker(items: whiteBalanceOptions, selectedIndex: selectedWbIndex, onChanged: onWb);
      case 'EV':
        return EVSlider(value: ev, onChanged: onEv);
      case 'MF':
        return ControlValuePicker(items: focusDistanceOptions, selectedIndex: selectedFocusIndex, onChanged: onMf);
      case 'MTR':
        return ControlValuePicker(
            items: _meteringModes, selectedIndex: selectedMeteringIndex, onChanged: onMetering);
      default:
        return const SizedBox.shrink();
    }
  }
}

class ControlChip extends StatelessWidget {
  final String label, value;
  final bool active;
  final VoidCallback onTap;

  const ControlChip({
    super.key,
    required this.label,
    required this.value,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? cameraAccentGold.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: active ? cameraAccentGold : Colors.white12,
              width: active ? 1.5 : 1.0,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: cameraAccentGold.withValues(alpha: 0.1),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: active ? cameraAccentGold : Colors.white38,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  color: active ? cameraAccentGold : cameraTextColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
}

class ControlValuePicker extends StatelessWidget {
  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const ControlValuePicker({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemBuilder: (_, i) {
            final active = i == selectedIndex;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: active
                      ? cameraAccentGold.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active ? cameraAccentGold : Colors.white12,
                    width: active ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      items[i],
                      style: TextStyle(
                        color: active ? cameraAccentGold : Colors.white60,
                        fontSize: 12,
                        fontWeight: active ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    if (active) ...[
                      const SizedBox(height: 2),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: cameraAccentGold,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      );
}

class EVSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const EVSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const Text('−3',
              style: TextStyle(color: Colors.white38, fontSize: 10)),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: cameraAccentGold,
                inactiveTrackColor: Colors.white24,
                thumbColor: cameraAccentGold,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                trackHeight: 2,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                  value: value,
                  min: -3,
                  max: 3,
                  divisions: 12,
                  onChanged: onChanged),
            ),
          ),
          const Text('+3',
              style: TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(width: 10),
          SizedBox(
            width: 38,
            child: Text(
              value >= 0
                  ? '+${value.toStringAsFixed(1)}'
                  : value.toStringAsFixed(1),
              style: const TextStyle(
                  color: cameraAccentGold, fontSize: 12, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
}

class ManualControlsRow extends StatelessWidget {
  final String iso;
  final String shutter;
  final String wb;
  final double ev;
  final String mf;

  const ManualControlsRow({
    super.key,
    required this.iso,
    required this.shutter,
    required this.wb,
    required this.ev,
    required this.mf,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      ('ISO', iso),
      ('SS', shutter),
      ('WB', wb),
      ('EV', ev >= 0 ? '+${ev.toStringAsFixed(1)}' : ev.toStringAsFixed(1)),
      ('MF', mf),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: items
          .map(
            (item) => Container(
              width: 52,
              height: 52,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black54,
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.$1,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}


