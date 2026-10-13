import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/player_service.dart';
import 'cover_image.dart';

/// 底部迷你播放器：有当前单集时显示。
/// 封面 + 标题/播客名 + 播放暂停按钮，顶部一条细进度条；点击进入播放页。
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final episode = player.current;
    if (episode == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final duration = player.duration?.inMilliseconds ?? 0;
    final position = player.position.inMilliseconds;
    final progress =
        duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;

    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed('/player'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部细进度条
            SizedBox(
              height: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  CoverImage(
                    url: episode.podcastImage,
                    size: 44,
                    radius: 8,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          episode.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          episode.podcastTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      player.playing
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill,
                      size: 36,
                    ),
                    color: theme.colorScheme.primary,
                    onPressed: () => player.toggle(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
