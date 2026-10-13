import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/xyz_service.dart';
import '../widgets/cover_image.dart';
import '../widgets/detail_scaffold.dart';
import '../widgets/episode_tile.dart';
import '../widgets/podcast_card.dart';

/// 播客详情页。路由参数为 pid（String）。
class PodcastDetailScreen extends StatefulWidget {
  final String pid;

  const PodcastDetailScreen({super.key, required this.pid});

  @override
  State<PodcastDetailScreen> createState() => _PodcastDetailScreenState();
}

class _PodcastDetailScreenState extends State<PodcastDetailScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  Podcast _podcast = const Podcast();
  bool _subscribed = false;
  bool _starred = false;
  bool _descExpanded = false;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final podcast =
          await context.read<XyzService>().podcastDetail(widget.pid);
      if (!mounted) return;
      setState(() {
        _podcast = podcast;
        _subscribed = podcast.isSubscribed;
        _starred = podcast.isStarred;
        _loading = false;
      });
    } on XyzException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
        _loading = false;
      });
    }
  }

  bool _requireLogin() {
    if (context.read<AuthService>().loggedIn) return true;
    Navigator.pushNamed(context, '/login');
    return false;
  }

  Future<void> _toggleSubscribe() async {
    if (!_requireLogin()) return;
    final target = !_subscribed;
    try {
      await context
          .read<XyzService>()
          .updateSubscription(widget.pid, target);
      if (!mounted) return;
      setState(() => _subscribed = target);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(target ? '已订阅' : '已取消订阅')),
      );
    } on XyzException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失败：$e')));
    }
  }

  Future<void> _toggleStar() async {
    if (!_requireLogin()) return;
    final target = !_starred;
    try {
      await context
          .read<XyzService>()
          .updateStarSubscription(widget.pid, target);
      if (!mounted) return;
      setState(() => _starred = target);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(target ? '已加星标' : '已取消星标')),
      );
    } on XyzException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      child: Scaffold(
        appBar: AppBar(title: Text(_podcast.title.isEmpty ? '播客' : _podcast.title)),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    return Column(
      children: [
        _buildHeader(),
        TabBar(
          controller: _tabController,
          tabs: const [Tab(text: '单集'), Tab(text: '最受欢迎'), Tab(text: '相关节目')],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _EpisodeListTab(pid: widget.pid),
              _PopularTab(pid: widget.pid),
              _RelatedTab(pid: widget.pid),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final p = _podcast;
    final desc = p.description.isNotEmpty ? p.description : p.brief;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverImage(url: p.image, size: 120, radius: 16),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    if (p.author.isNotEmpty)
                      Text(
                        p.author,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (p.episodeCount > 0) '${p.episodeCount} 期',
                        if (p.subscriptionCount > 0)
                          '${formatPlayCount(p.subscriptionCount)} 订阅',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(() => _descExpanded = !_descExpanded),
              child: Text(
                desc,
                maxLines: _descExpanded ? null : 3,
                overflow:
                    _descExpanded ? null : TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _toggleSubscribe,
                  icon: Icon(
                      _subscribed ? Icons.check : Icons.add, size: 18),
                  label: Text(_subscribed ? '已订阅' : '订阅'),
                  style: _subscribed
                      ? FilledButton.styleFrom(
                          backgroundColor: theme
                              .colorScheme.surfaceContainerHighest,
                          foregroundColor: theme.colorScheme.onSurface,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              IconButton.outlined(
                onPressed: _toggleStar,
                icon: Icon(
                  _starred ? Icons.star : Icons.star_outline,
                  color: _starred ? Colors.amber : null,
                ),
                tooltip: _starred ? '取消星标' : '星标订阅',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 单集 tab：episodeList 分页（新到旧）。
class _EpisodeListTab extends StatefulWidget {
  final String pid;
  const _EpisodeListTab({required this.pid});

  @override
  State<_EpisodeListTab> createState() => _EpisodeListTabState();
}

class _EpisodeListTabState extends State<_EpisodeListTab>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<Episode> _episodes = [];
  Map<String, dynamic>? _loadMoreKey;
  bool _loadingMore = false;
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        !_loadingMore &&
        _loadMoreKey != null &&
        !_loading) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _episodes = [];
      _loadMoreKey = null;
    });
    try {
      final paged =
          await context.read<XyzService>().episodeList(widget.pid);
      if (!mounted) return;
      setState(() {
        _episodes = paged.items;
        _loadMoreKey = paged.loadMoreKey;
        _loading = false;
      });
    } on XyzException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loadMoreKey == null) return;
    setState(() => _loadingMore = true);
    try {
      final paged = await context.read<XyzService>().episodeList(
            widget.pid,
            loadMoreKey: _loadMoreKey,
          );
      if (!mounted) return;
      setState(() {
        _episodes.addAll(paged.items);
        _loadMoreKey = paged.loadMoreKey;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_episodes.isEmpty) return const Center(child: Text('暂无单集'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _episodes.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _episodes.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return EpisodeTile(
            episode: _episodes[i],
            episodes: _episodes,
            index: i,
            showPodcast: false,
          );
        },
      ),
    );
  }
}

/// 最受欢迎 tab。
class _PopularTab extends StatefulWidget {
  final String pid;
  const _PopularTab({required this.pid});

  @override
  State<_PopularTab> createState() => _PopularTabState();
}

class _PopularTabState extends State<_PopularTab>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  List<Episode> _episodes = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final episodes =
          await context.read<XyzService>().popularEpisodes(widget.pid);
      if (!mounted) return;
      setState(() {
        _episodes = episodes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_episodes.isEmpty) return const Center(child: Text('暂无数据'));
    return ListView.builder(
      itemCount: _episodes.length,
      itemBuilder: (context, i) => EpisodeTile(
        episode: _episodes[i],
        episodes: _episodes,
        index: i,
        showPodcast: false,
      ),
    );
  }
}

/// 相关节目 tab。
class _RelatedTab extends StatefulWidget {
  final String pid;
  const _RelatedTab({required this.pid});

  @override
  State<_RelatedTab> createState() => _RelatedTabState();
}

class _RelatedTabState extends State<_RelatedTab>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  List<Podcast> _podcasts = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final podcasts =
          await context.read<XyzService>().relatedPodcasts(widget.pid);
      if (!mounted) return;
      setState(() {
        _podcasts = podcasts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_podcasts.isEmpty) return const Center(child: Text('暂无相关节目'));
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemCount: _podcasts.length,
      itemBuilder: (context, i) {
        final p = _podcasts[i];
        return PodcastCard(
          podcast: p,
          width: double.infinity,
          onTap: () => Navigator.pushNamed(
            context,
            '/podcast',
            arguments: p.pid,
          ),
        );
      },
    );
  }
}
