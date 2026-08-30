import 'package:flutter/material.dart';

class StreakBadge extends StatelessWidget {
  final int current;
  final int best;

  const StreakBadge({super.key, required this.current, required this.best});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🔥', style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Text(
            '$current day streak',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.orange.shade900,
            ),
          ),
          if (best > 0) ...[
            const SizedBox(width: 6),
            Text(
              '· best $best',
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
