import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/player_service.dart';
import '../services/xyz_service.dart';
import '../widgets/cover_image.dart';

/// 播放页（Apple Music 风格）：大圆角封面、标题/播客名、
/// 细进度条 + 已播/剩余时间、大播放控制按钮、倍速/播放模式，
/// Tab 切换[封面|简介]，简介页展示单集描述。
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isFavorite = false;
  bool _isSubscribed = false;
  bool _subLoading = false;
  String? _lastEid;

  static const _speeds = [1.0, 1.25, 1.5, 2.0, 0.75];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 单集变化时同步收藏/订阅状态
  void _syncEpisodeState(Episode episode) {
    if (episode.eid == _lastEid) return;
    _lastEid = episode.eid;
    _isFavorite = episode.isFavorite;
    _isSubscribed = false;
    // 拉取播客详情确认订阅状态（失败则保持未订阅显示）
    final xyz = context.read<XyzService>();
    if (episode.podcastPid.isNotEmpty) {
      xyz.podcastDetail(episode.podcastPid).then((pod) {
        if (!mounted || episode.eid != _lastEid) return;
        setState(() => _isSubscribed = pod.isSubscribed);
      }).catchError((_) {});
    }
  }

  String _stripHtml(String html) {
    if (html.isEmpty) return '';
    var text = html.replaceAll(RegExp(r'<[^>]*>'), '');
    const entities = {
      '&nbsp;': ' ',
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
    };
    entities.forEach((k, v) => text = text.replaceAll(k, v));
    // 压缩多余空行
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _toggleFavorite(Episode episode) async {
    final auth = context.read<AuthService>();
    if (!auth.loggedIn) {
      if (mounted) Navigator.of(context).pushNamed('/login');
      return;
    }
    final xyz = context.read<XyzService>();
    final target = !_isFavorite;
    setState(() => _isFavorite = target);
    try {
      await xyz.updateFavorite(episode.eid, target);
    } on XyzException catch (e) {
      if (mounted) setState(() => _isFavorite = !target);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _toggleSubscribe(Episode episode) async {
    final auth = context.read<AuthService>();
    if (!auth.loggedIn) {
      if (mounted) Navigator.of(context).pushNamed('/login');
      return;
    }
    if (episode.podcastPid.isEmpty || _subLoading) return;
    final xyz = context.read<XyzService>();
    final target = !_isSubscribed;
    setState(() {
      _subLoading = true;
      _isSubscribed = target;
    });
    try {
      await xyz.updateSubscription(episode.podcastPid, target);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(target ? '已订阅' : '已取消订阅')),
        );
      }
    } on XyzException catch (e) {
      if (mounted) setState(() => _isSubscribed = !target);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _subLoading = false);
    }
  }

  void _cycleSpeed(PlayerService player) {
    final idx = _speeds.indexOf(player.speed);
    final next = _speeds[(idx + 1) % _speeds.length];
    player.setSpeed(next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('倍速 ${next}x'),
        duration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final episode = player.current;

    if (episode == null) {
      return const Scaffold(
        body: Center(child: Text('没有正在播放的单集')),
      );
    }
    _syncEpisodeState(episode);

    final theme = Theme.of(context);
    final duration = player.duration ?? episode.duration;
    final position = player.position;
    final remaining = duration - position;

    return GestureDetector(
      // 移动端下滑关闭播放页
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null &&
            details.primaryVelocity! > 400) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: TabBar(
            controller: _tabController,
            dividerColor: Colors.transparent,
            tabs: const [Tab(text: '封面'), Tab(text: '简介')],
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.more_horiz),
              onPressed: () => _showMoreSheet(context, episode),
            ),
          ],
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildCoverTab(context, player, episode, duration, position,
                remaining, theme),
            _buildNotesTab(context, episode),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverTab(
    BuildContext context,
    PlayerService player,
    Episode episode,
    Duration duration,
    Duration position,
    Duration remaining,
    ThemeData theme,
  ) {
    final maxMs = duration.inMilliseconds > 0 ? duration.inMilliseconds : 1;
    final posMs = position.inMilliseconds.clamp(0, maxMs);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          // 桌面宽屏下限制内容宽度，封面不再撑满
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                // 大圆角封面
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: CoverImage(
                    url: episode.coverUrl,
                    size: 400,
                    radius: 20,
                  ),
                ),
            const SizedBox(height: 28),
            // 标题 / 播客名
            Text(
              episode.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: episode.podcastPid.isEmpty
                  ? null
                  : () => Navigator.of(context)
                      .pushNamed('/podcast', arguments: episode.podcastPid),
              child: Text(
                episode.podcastTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // 进度条
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: posMs.toDouble(),
                max: maxMs.toDouble(),
                onChanged: (v) =>
                    player.seek(Duration(milliseconds: v.toInt())),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(position),
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant)),
                Text('-${_fmt(remaining.isNegative ? Duration.zero : remaining)}',
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 8),
            // 播放控制
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.skip_previous),
                  onPressed: () => player.prev(),
                ),
                IconButton(
                  iconSize: 64,
                  color: theme.colorScheme.primary,
                  icon: Icon(player.playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill),
                  onPressed: () => player.toggle(),
                ),
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.skip_next),
                  onPressed: () => player.next(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 倍速 / 模式 / 收藏 / 评论 / 订阅
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => _cycleSpeed(player),
                  child: Text('${player.speed}x',
                      style: const TextStyle(fontSize: 13)),
                ),
                IconButton(
                  tooltip: player.modeLabel,
                  icon: Icon(
                    switch (player.mode) {
                      PlayMode.sequence => Icons.repeat,
                      PlayMode.loop => Icons.repeat,
                      PlayMode.single => Icons.repeat_one,
                      PlayMode.shuffle => Icons.shuffle,
                    },
                    size: 22,
                  ),
                  onPressed: () {
                    player.cycleMode();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(player.modeLabel),
                        duration: const Duration(milliseconds: 800),
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: '收藏',
                  icon: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                    size: 22,
                  ),
                  color: _isFavorite ? Colors.red : null,
                  onPressed: () => _toggleFavorite(episode),
                ),
                IconButton(
                  tooltip: '评论',
                  icon: Badge(
                    label: Text('${episode.commentCount}'),
                    isLabelVisible: episode.commentCount > 0,
                    child: const Icon(Icons.comment_outlined, size: 22),
                  ),
                  onPressed: () => Navigator.of(context)
                      .pushNamed('/comments', arguments: episode),
                ),
                IconButton(
                  tooltip: _isSubscribed ? '已订阅' : '订阅播客',
                  icon: Icon(
                    _isSubscribed
                        ? Icons.notifications
                        : Icons.notifications_outlined,
                    size: 22,
                  ),
                  onPressed:
                      _subLoading ? null : () => _toggleSubscribe(episode),
                ),
              ],
            ),
            if (player.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  player.errorMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            const Spacer(flex: 3),
          ],
        ),
      ),
    ),
    ),
  );
  }

  Widget _buildNotesTab(BuildContext context, Episode episode) {
    final notes = _stripHtml(
        episode.shownotes.isNotEmpty ? episode.shownotes : episode.description);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          episode.title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '${episode.displayDate} · ${episode.podcastTitle}',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const Divider(height: 28),
        SelectableText(
          notes.isEmpty ? '暂无简介' : notes,
          style: const TextStyle(fontSize: 15, height: 1.7),
        ),
      ],
    );
  }

  void _showMoreSheet(BuildContext context, Episode episode) {
    final player = context.read<PlayerService>();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('下一首播放'),
              onTap: () {
                Navigator.of(ctx).pop();
                player.playNext(episode);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已添加到下一首播放')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text('播放队列（${player.queue.length}）'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showQueueSheet(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showQueueSheet(BuildContext context) {
    final player = context.read<PlayerService>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controller) => ListView.builder(
          controller: controller,
          itemCount: player.queue.length,
          itemBuilder: (_, i) {
            final e = player.queue[i];
            final selected = i == player.index;
            return ListTile(
              selected: selected,
              leading: CoverImage(url: e.coverUrl, size: 44, radius: 6),
              title: Text(e.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(e.podcastTitle,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  player.removeAt(i);
                  Navigator.of(ctx).pop();
                },
              ),
              onTap: () {
                player.jumpTo(i);
                Navigator.of(ctx).pop();
              },
            );
          },
        ),
      ),
    );
  }
}
