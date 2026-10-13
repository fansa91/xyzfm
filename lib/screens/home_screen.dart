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
  List<Episode> _forYou = []; // 为你推荐
  List<Episode> _editorPicks = []; // 编辑精选
  List<Podcast> _pilotShows = []; // 为你精选的节目
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
      // 新增的三个分区，失败不阻塞
      List<Episode> forYou = [];
      List<Episode> editorPicks = [];
      List<Podcast> pilotShows = [];
      try {
        forYou = await svc.recommendEpisodes();
      } catch (_) {}
      try {
        editorPicks = await svc.editorPicks();
      } catch (_) {}
      try {
        pilotShows = await svc.pilotDiscovery();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _sections = sections;
        _charts = charts;
        _forYou = forYou;
        _editorPicks = editorPicks;
        _pilotShows = pilotShows;
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
        itemCount: _sections.length +
            (_forYou.isEmpty ? 0 : 1) +
            (_editorPicks.isEmpty ? 0 : 1) +
            (_pilotShows.isEmpty ? 0 : 1) +
            (_charts.isEmpty ? 0 : 1),
        itemBuilder: (context, i) {
          if (i < _sections.length) return _buildSection(_sections[i], i);
          var j = i - _sections.length;
          if (_forYou.isNotEmpty) {
            if (j == 0) return _buildEpisodeSection('为你推荐', _forYou);
            j--;
          }
          if (_editorPicks.isNotEmpty) {
            if (j == 0) return _buildEpisodeSection('编辑精选', _editorPicks);
            j--;
          }
          if (_pilotShows.isNotEmpty) {
            if (j == 0) return _buildPilotSection();
            j--;
          }
          return _buildCharts();
        },
      ),
    );
  }

  /// 横滑单集分区（为你推荐 / 编辑精选）。
  Widget _buildEpisodeSection(String title, List<Episode> episodes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        SizedBox(
          height: 148,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: episodes.length.clamp(0, 10),
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, k) {
              final ep = episodes[k];
              return InkWell(
                onTap: () => context
                    .read<PlayerService>()
                    .playQueue(episodes, k),
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 120,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CoverImage(url: ep.coverUrl, size: 120, radius: 12),
                      const SizedBox(height: 6),
                      Text(
                        ep.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, height: 1.3),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// 为你精选的节目：横滑节目卡片。
  Widget _buildPilotSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '为你精选的节目'),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _pilotShows.length.clamp(0, 10),
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, k) {
              final p = _pilotShows[k];
              return PodcastCard(
                podcast: p,
                width: 120,
                onTap: () =>
                    Navigator.pushNamed(context, '/podcast', arguments: p.pid),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
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
    final charts = <TopChart>[];
    final categories = <String>[];
    for (int i = 0; i < _charts.length && i < _chartCategories.length; i++) {
      if (_charts[i].episodes.isNotEmpty) {
        charts.add(_charts[i]);
        categories.add(_chartCategories[i]);
      }
    }
    if (charts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '榜单'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          // 最热 / 锋芒 / 新星三张卡片一横排
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < charts.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: i == 0 ? 0 : 6,
                      right: i == charts.length - 1 ? 0 : 6,
                    ),
                    child: _ChartCard(
                      chart: charts[i],
                      category: categories[i],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
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

/// 榜单卡片：标题 + 前三名（排名+标题），点卡片进榜单详情，点单集播放。
class _ChartCard extends StatelessWidget {
  final TopChart chart;
  final String category;

  const _ChartCard({required this.chart, required this.category});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eps = chart.episodes.take(3).toList();
    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pushNamed(
          context,
          '/chart',
          arguments: {'title': chart.title, 'category': category},
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                chart.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              for (int i = 0; i < eps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    onTap: () => context
                        .read<PlayerService>()
                        .playQueue(chart.episodes, i),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontStyle: FontStyle.italic,
                              color: i == 0
                                  ? Colors.red
                                  : i == 1
                                      ? Colors.orange
                                      : i == 2
                                          ? Colors.amber.shade700
                                          : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            eps[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
