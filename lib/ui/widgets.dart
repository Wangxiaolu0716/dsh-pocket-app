import 'package:flutter/material.dart';

import '../theme.dart';

/// 状态圆点：绿=通，红=不通，灰=还没测。
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.state, this.size = 8});

  final ProbeDotState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      ProbeDotState.online => dshOnline,
      ProbeDotState.offline => dshOffline,
      ProbeDotState.unknown => Theme.of(context).colorScheme.outline,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

enum ProbeDotState { unknown, online, offline }

/// 小标签：线路名 + 地址。
class LineChip extends StatelessWidget {
  const LineChip({
    super.key,
    required this.label,
    required this.address,
    required this.state,
  });

  final String label;
  final String address;
  final ProbeDotState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(state: state),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              address,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
