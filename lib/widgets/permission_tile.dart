import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme.dart';

/// Reusable widget showing a permission row with status indicator and retry button.
class PermissionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final PermissionStatus status;
  final VoidCallback? onRequest;

  const PermissionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.onRequest,
  });

  Color get _statusColor {
    if (status.isGranted) return AppTheme.successColor;
    if (status.isPermanentlyDenied) return AppTheme.errorColor;
    return AppTheme.warningColor;
  }

  IconData get _statusIcon {
    if (status.isGranted) return Icons.check_circle_rounded;
    if (status.isPermanentlyDenied) return Icons.block_rounded;
    return Icons.radio_button_unchecked_rounded;
  }

  String get _statusLabel {
    if (status.isGranted) return 'Granted';
    if (status.isPermanentlyDenied) return 'Blocked (open Settings)';
    return 'Not granted';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _statusColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primaryColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(_statusIcon, size: 14, color: _statusColor),
                    const SizedBox(width: 4),
                    Text(_statusLabel,
                        style: TextStyle(
                            fontSize: 12,
                            color: _statusColor,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
          ),
          if (!status.isGranted && onRequest != null)
            TextButton(
              onPressed: status.isPermanentlyDenied
                  ? () => openAppSettings()
                  : onRequest,
              child: Text(
                status.isPermanentlyDenied ? 'Settings' : 'Allow',
                style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}
