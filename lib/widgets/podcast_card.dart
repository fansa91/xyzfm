import 'package:flutter/material.dart';

import '../models/models.dart';
import 'cover_image.dart';

/// 播客节目卡片：竖向布局（封面 + 标题 + 作者/单集数），用于横向列表与网格。
class PodcastCard extends StatelessWidget {
  final Podcast podcast;
  final double width;
  final VoidCallback? onTap;

  const PodcastCard({
    super.key,
    required this.podcast,
    this.width = 120,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Grid 里传 double.infinity 时取实际可用宽度，避免 CoverImage 无限尺寸
          final w = width.isFinite
              ? width
              : (constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 120.0);
          return SizedBox(
            width: w,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                CoverImage(url: podcast.image, size: w, radius: 12),
                const SizedBox(height: 8),
                Text(
                  podcast.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  podcast.author.isNotEmpty
                      ? podcast.author
                      : (podcast.episodeCount > 0
                          ? '${podcast.episodeCount} 期节目'
                          : ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
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
