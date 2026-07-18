import 'package:flutter/material.dart';
import 'camera_ui_colors.dart';

class TopBarControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;

  const TopBarControlButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.36),
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: IconButton(
          icon: Icon(icon, color: active ? cameraAccentGold : Colors.white, size: 22),
          onPressed: onPressed,
        ),
      );
}
