import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../models/models.dart';
import '../services/xyz_service.dart';
import '../widgets/episode_tile.dart';
import '../widgets/podcast_card.dart';

/// 搜索页：搜索框 + 热词 + TabBar[节目 | 单集]。
class SearchScreen extends StatefulWidget {
  final bool autofocus;

  const SearchScreen({super.key, this.autofocus = false});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  late final TabController _tabController;
  List<String> _presets = [];
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _tabController = TabController(length: 2, vsync: this);
    _loadPresets();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).requestFocus(_searchFocus);
      });
    }
  }

  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _tabController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadPresets() async {
    try {
      final presets = await context.read<XyzService>().searchPreset();
      if (!mounted) return;
      setState(() => _presets = presets);
    } catch (_) {
      // 热词失败不阻塞
    }
  }

  void _submit(String value) {
    final keyword = value.trim();
    if (keyword.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _keyword = keyword);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _searchFocus,
          autofocus: widget.autofocus,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '搜索节目、单集',
            border: InputBorder.none,
            hintStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _keyword = '');
                    },
                  )
                : null,
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: _submit,
        ),
      ),
      body: _keyword.isEmpty ? _buildPresets() : _buildResults(),
    );
  }

  Widget _buildPresets() {
    if (_presets.isEmpty) {
      return const Center(
        child: Text('输入关键词搜索感兴趣的播客', style: TextStyle(fontSize: 14)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('大家都在搜',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _presets
              .map(
                (p) => ActionChip(
                  label: Text(p),
                  onPressed: () {
                    _controller.text = p;
                    _submit(p);
                  },
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildResults() {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [Tab(text: '节目'), Tab(text: '单集')],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _ResultList(key: ValueKey('p:$_keyword'), keyword: _keyword, type: 'podcast'),
              _ResultList(key: ValueKey('e:$_keyword'), keyword: _keyword, type: 'episode'),
            ],
          ),
        ),
      ],
    );
  }
}

/// 单个 tab 的搜索结果列表（分页）。
class _ResultList extends StatefulWidget {
  final String keyword;
  final String type; // podcast | episode

  const _ResultList({super.key, required this.keyword, required this.type});

  @override
  State<_ResultList> createState() => _ResultListState();
}

class _ResultListState extends State<_ResultList> {
  bool _loading = true;
  String? _error;
  List<Podcast> _podcasts = [];
  List<Episode> _episodes = [];
  Map<String, dynamic>? _loadMoreKey;
  bool _loadingMore = false;
  final ScrollController _scrollController = ScrollController();

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
      _podcasts = [];
      _episodes = [];
      _loadMoreKey = null;
    });
    try {
      final result = await context
          .read<XyzService>()
          .search(widget.keyword, widget.type);
      if (!mounted) return;
      setState(() {
        _podcasts = result.podcasts;
        _episodes = result.episodes;
        _loadMoreKey = result.loadMoreKey;
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
        _error = '搜索失败：$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loadMoreKey == null) return;
    setState(() => _loadingMore = true);
    try {
      final result = await context.read<XyzService>().search(
            widget.keyword,
            widget.type,
            loadMoreKey: _loadMoreKey,
          );
      if (!mounted) return;
      setState(() {
        _podcasts.addAll(result.podcasts);
        _episodes.addAll(result.episodes);
        _loadMoreKey = result.loadMoreKey;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
    if (widget.type == 'podcast') {
      if (_podcasts.isEmpty) {
        return const Center(child: Text('没有找到相关节目'));
      }
      return GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
          childAspectRatio: 0.62,
        ),
        itemCount: _podcasts.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _podcasts.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final p = _podcasts[i];
          return PodcastCard(
            podcast: p,
            width: double.infinity,
            onTap: () =>
                Navigator.pushNamed(context, '/podcast', arguments: p.pid),
          );
        },
      );
    }
    if (_episodes.isEmpty) {
      return const Center(child: Text('没有找到相关单集'));
    }
    return ListView.builder(
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
        );
      },
    );
  }
}
