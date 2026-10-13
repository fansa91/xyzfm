import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/xyz_service.dart';
import '../widgets/episode_tile.dart';
import '../widgets/podcast_card.dart';

/// 订阅页：TabBar[我的订阅 | 订阅更新]。
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('订阅', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: const TabBar(
          tabs: [Tab(text: '我的订阅'), Tab(text: '订阅更新')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_MySubscriptions(), _InboxList()],
      ),
    );
  }
}

/// 需要登录的占位
class _NeedLogin extends StatelessWidget {
  const _NeedLogin();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.login, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('登录后查看订阅内容'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pushNamed(context, '/login'),
            child: const Text('去登录'),
          ),
        ],
      ),
    );
  }
}

/// 我的订阅：两列网格 + 分页（skip += 20），长按取消订阅。
class _MySubscriptions extends StatefulWidget {
  const _MySubscriptions();

  @override
  State<_MySubscriptions> createState() => _MySubscriptionsState();
}

class _MySubscriptionsState extends State<_MySubscriptions> {
  bool _loading = true;
  String? _error;
  List<Podcast> _items = [];
  bool _loadingMore = false;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
        _hasMore &&
        !_loading) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _items = [];
      _hasMore = true;
    });
    try {
      final paged = await context.read<XyzService>().subscriptions();
      if (!mounted) return;
      setState(() {
        _items = paged.items;
        _hasMore = paged.hasMore;
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
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final paged =
          await context.read<XyzService>().subscriptions(skip: _items.length);
      if (!mounted) return;
      setState(() {
        _items.addAll(paged.items);
        _hasMore = paged.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _unsubscribe(Podcast p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('取消订阅'),
        content: Text('确定取消订阅「${p.title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('再想想'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('取消订阅'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await context.read<XyzService>().updateSubscription(p.pid, false);
      if (!mounted) return;
      setState(() => _items.removeWhere((e) => e.pid == p.pid));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已取消订阅')));
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
    final loggedIn = context.watch<AuthService>().loggedIn;
    if (!loggedIn) return const _NeedLogin();
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
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text('还没有订阅，去发现页找喜欢的节目吧')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.72,
        ),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final p = _items[i];
          return GestureDetector(
            onLongPress: () => _unsubscribe(p),
            child: PodcastCard(
              podcast: p,
              width: double.infinity,
              onTap: () =>
                  Navigator.pushNamed(context, '/podcast', arguments: p.pid),
            ),
          );
        },
      ),
    );
  }
}

/// 订阅更新：inboxList 的单集列表，点击播放。
class _InboxList extends StatefulWidget {
  const _InboxList();

  @override
  State<_InboxList> createState() => _InboxListState();
}

class _InboxListState extends State<_InboxList> {
  bool _loading = true;
  String? _error;
  List<Episode> _episodes = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final episodes = await context.read<XyzService>().inboxList();
      if (!mounted) return;
      setState(() {
        _episodes = episodes;
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

  @override
  Widget build(BuildContext context) {
    final loggedIn = context.watch<AuthService>().loggedIn;
    if (!loggedIn) return const _NeedLogin();
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
    if (_episodes.isEmpty) {
      return const Center(child: Text('订阅的节目还没有更新'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _episodes.length,
        itemBuilder: (context, i) => EpisodeTile(
          episode: _episodes[i],
          episodes: _episodes,
          index: i,
        ),
      ),
    );
  }
}
