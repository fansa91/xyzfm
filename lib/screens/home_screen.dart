import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../models/models.dart';
import '../services/player_service.dart';
import '../services/xyz_service.dart';
import '../widgets/cover_image.dart';
import '../widgets/episode_tile.dart';
import '../widgets/podcast_card.dart';
import '../widgets/section_header.dart';

/// 发现页：discovery 分区（榜单/精选/大家都在听）+ 底部三大榜单。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  String? _error;
  List<DiscoverySection> _sections = [];
  List<TopChart> _charts = [];
  bool _refreshingRecommend = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = context.read<XyzService>();
      final sections = await svc.discovery();
      List<TopChart> charts = [];
      try {
        charts = await svc.topList();
      } catch (_) {
        // 榜单失败不影响主体内容
      }
      if (!mounted) return;
      setState(() {
        _sections = sections;
        _charts = charts;
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

  /// “大家都在听”换一换
  Future<void> _refreshRecommend(int sectionIndex) async {
    if (_refreshingRecommend) return;
    setState(() => _refreshingRecommend = true);
    try {
      final episodes =
          await context.read<XyzService>().refreshEpisodeRecommend();
      if (!mounted) return;
      setState(() {
        final old = _sections[sectionIndex];
        _sections[sectionIndex] = DiscoverySection(
          title: old.title,
          targetType: 'EPISODE',
          episodes: episodes,
        );
        _refreshingRecommend = false;
      });
    } on XyzException catch (e) {
      if (!mounted) return;
      setState(() => _refreshingRecommend = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _refreshingRecommend = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('刷新失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('xyzFM', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () =>
                Navigator.pushNamed(context, '/search', arguments: true),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildSkeleton();
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _sections.length + (_charts.isEmpty ? 0 : 1),
        itemBuilder: (context, i) {
          if (i < _sections.length) return _buildSection(_sections[i], i);
          return _buildCharts();
        },
      ),
    );
  }

  Widget _buildSection(DiscoverySection section, int index) {
    final isRecommend = section.title.contains('都在听');
    final header = isRecommend
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
            child: Row(
              children: [
                Text(
                  section.title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _refreshRecommend(index),
                  icon: _refreshingRecommend
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 16),
                  label: const Text('换一换', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          )
        : SectionHeader(title: section.title);

    if (section.targetType == 'PODCAST' && section.podcasts.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: section.podcasts.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, j) {
                final p = section.podcasts[j];
                return PodcastCard(
                  podcast: p,
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/podcast',
                    arguments: p.pid,
                  ),
                );
              },
            ),
          ),
        ],
      );
    }
    if (section.targetType == 'EPISODE' && section.episodes.isNotEmpty) {
      final episodes = section.episodes;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          ...episodes.asMap().entries.map(
                (e) => EpisodeTile(
                  episode: e.value,
                  episodes: episodes,
                  index: e.key,
                ),
              ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  static const _chartCategories = ['HOT', 'ROCK', 'NEW'];

  Widget _buildCharts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _charts.length; i++)
          _buildChartRow(_charts[i], _chartCategories[i]),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildChartRow(TopChart chart, String category) {
    if (chart.episodes.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: chart.title,
          onMore: () => Navigator.pushNamed(
            context,
            '/chart',
            arguments: {'title': chart.title, 'category': category},
          ),
        ),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: chart.episodes.length.clamp(0, 10),
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, j) {
              final ep = chart.episodes[j];
              return _ChartEpisodeCard(episode: ep, rank: j + 1);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSkeleton() {
    final ph = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: ph,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: ph,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 12,
                    width: 140,
                    decoration: BoxDecoration(
                      color: ph,
                      borderRadius: BorderRadius.circular(4),
                    ),
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

/// 榜单横向小卡片：排名 + 封面 + 标题，点击按榜单队列播放。
class _ChartEpisodeCard extends StatelessWidget {
  final Episode episode;
  final int rank;

  const _ChartEpisodeCard({required this.episode, required this.rank});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        // 找到所在榜单的完整列表，按队列播放
        final state = context.findAncestorStateOfType<_HomeScreenState>();
        final charts = state?._charts ?? const <TopChart>[];
        TopChart? chart;
        for (final c in charts) {
          if (c.episodes.any((e) => e.eid == episode.eid)) {
            chart = c;
            break;
          }
        }
        final list =
            (chart != null && chart.episodes.isNotEmpty) ? chart.episodes : [episode];
        final idx = list.indexWhere((e) => e.eid == episode.eid);
        context.read<PlayerService>().playQueue(list, idx < 0 ? 0 : idx);
      },
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 240,
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                  color: rank <= 3
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            CoverImage(url: episode.coverUrl, size: 64, radius: 8),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.3),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    episode.podcastTitle,
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
          ],
        ),
      ),
    );
  }
}
