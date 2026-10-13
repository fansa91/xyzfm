import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../services/player_service.dart';
import '../services/xyz_service.dart';
import 'cover_image.dart';

/// 单集行：封面、标题、播客名、时长 + 日期、底部细播放进度条、右侧更多菜单。
///
/// onTap 默认播放：若提供了 [episodes]（所在列表），则按列表队列从 [index] 开始播；
/// 否则只播放这一集。
class EpisodeTile extends StatefulWidget {
  final Episode episode;
  final List<Episode>? episodes;
  final int? index;
  final bool showPodcast;

  const EpisodeTile({
    super.key,
    required this.episode,
    this.episodes,
    this.index,
    this.showPodcast = true,
  });

  @override
  State<EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<EpisodeTile> {
  late bool _favorite;

  @override
  void initState() {
    super.initState();
    _favorite = widget.episode.isFavorite;
  }

  @override
  void didUpdateWidget(covariant EpisodeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episode.eid != widget.episode.eid) {
      _favorite = widget.episode.isFavorite;
    }
  }

  Future<void> _play() async {
    final player = context.read<PlayerService>();
    final episodes = widget.episodes;
    final index = widget.index;
    if (episodes != null && episodes.isNotEmpty && index != null) {
      await player.playQueue(episodes, index);
    } else {
      await player.playEpisode(widget.episode);
    }
  }

  /// “下一首播放”：PlayerService 由另一代理并行编写，仅 playQueue/playEpisode/
  /// current 在契约内；这里用 dynamic 探测 playNext，缺失时回退为立即播放。
  Future<void> _playNext() async {
    final player = context.read<PlayerService>();
    try {
      await (player as dynamic).playNext(widget.episode);
    } catch (_) {
      await player.playEpisode(widget.episode);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已加入下一首播放'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _toggleFavorite() async {
    final svc = context.read<XyzService>();
    void snack(String msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
    final target = !_favorite;
    try {
      await svc.updateFavorite(widget.episode.eid, target);
      if (!mounted) return;
      setState(() => _favorite = target);
      snack(target ? '已收藏' : '已取消收藏');
    } on XyzException catch (e) {
      snack(e.message);
    } catch (e) {
      snack('操作失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ep = widget.episode;
    // 只订阅“当前播放 eid”，避免进度 tick 导致整行频繁 rebuild
    final isCurrent = context.select<PlayerService, bool>(
      (p) => p.current?.eid == ep.eid,
    );
    final progressRatio = ep.durationMs > 0 && ep.progressMs > 0
        ? (ep.progressMs / ep.durationMs).clamp(0.0, 1.0)
        : 0.0;

    return InkWell(
      onTap: _play,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CoverImage(url: ep.podcastImage, size: 56, radius: 8),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ep.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          color: isCurrent
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (widget.showPodcast && ep.podcastTitle.isNotEmpty)
                            ep.podcastTitle,
                          if (ep.displayDate.isNotEmpty) ep.displayDate,
                          formatDuration(ep.durationMs),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCurrent)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.equalizer,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onSelected: (v) {
                    switch (v) {
                      case 'play':
                        _play();
                      case 'next':
                        _playNext();
                      case 'fav':
                        _toggleFavorite();
                      case 'comment':
                        Navigator.pushNamed(
                          context,
                          '/comments',
                          arguments: ep,
                        );
                      case 'podcast':
                        if (ep.podcastPid.isNotEmpty) {
                          Navigator.pushNamed(
                            context,
                            '/podcast',
                            arguments: ep.podcastPid,
                          );
                        }
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'play', child: Text('立即播放')),
                    const PopupMenuItem(value: 'next', child: Text('下一首播放')),
                    PopupMenuItem(
                      value: 'fav',
                      child: Text(_favorite ? '取消收藏' : '收藏'),
                    ),
                    const PopupMenuItem(value: 'comment', child: Text('评论')),
                    const PopupMenuItem(value: 'podcast', child: Text('前往播客')),
                  ],
                ),
              ],
            ),
            if (progressRatio > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progressRatio,
                    minHeight: 3,
                    backgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
