import 'package:flutter/material.dart';

/// Circular visual indicator for a pose-match score.
class MatchIndicator extends StatelessWidget {
  final double value;
  final double size;

  const MatchIndicator({
    super.key,
    required this.value,
    this.size = 120.0,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = _getColor(value);

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
        ),

        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: value,
            strokeWidth: 8,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),

        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${(value * 100).toInt()}%',
              style: TextStyle(
                fontSize: size * 0.22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              'MATCH',
              style: TextStyle(
                fontSize: size * 0.08,
                fontWeight: FontWeight.w500,
                color: Colors.white70,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _getColor(double v) {
    if (v < 0.4) return Colors.redAccent;
    if (v < 0.7) return Colors.orangeAccent;
    if (v < 0.9) return Colors.lightGreenAccent;
    return const Color(0xFF00FFFF);
  }
}
