import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/player_service.dart';
import '../services/xyz_service.dart';
import '../widgets/cover_image.dart';
import '../widgets/detail_scaffold.dart';
import '../widgets/episode_tile.dart';

/// 我的：登录态 / 我的收藏 / 收听历史 / 设置入口。
class UserScreen extends StatelessWidget {
  const UserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (auth.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!auth.loggedIn) return _buildLoggedOut(context);
    return _buildLoggedIn(context, auth);
  }

  Widget _buildLoggedOut(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 32),
          Center(
            child: Icon(
              Icons.account_circle_outlined,
              size: 88,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              '还没有登录',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '登录后同步订阅、收藏与收听进度',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pushNamed('/login'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('登录 / 注册', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 24),
          _entryTile(
            context,
            icon: Icons.favorite_border,
            title: '我的收藏',
            onTap: () => _needLogin(context),
          ),
          _entryTile(
            context,
            icon: Icons.history,
            title: '收听历史',
            onTap: () => _needLogin(context),
          ),
          _entryTile(
            context,
            icon: Icons.settings_outlined,
            title: '设置',
            onTap: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoggedIn(BuildContext context, AuthService auth) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: ListView(
        children: [
          // 个人信息头
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CoverImage(url: auth.avatarUrl, size: 64, radius: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.nickname.isEmpty ? '播客听众' : auth.nickname,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (auth.bio.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          auth.bio,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _entryTile(
            context,
            icon: Icons.favorite_border,
            title: '我的收藏',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const DetailScaffold(child: _FavoriteScreen()),
              ),
            ),
          ),
          _entryTile(
            context,
            icon: Icons.history,
            title: '收听历史',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const DetailScaffold(child: _HistoryScreen()),
              ),
            ),
          ),
          _entryTile(
            context,
            icon: Icons.settings_outlined,
            title: '设置',
            onTap: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
    );
  }

  Widget _entryTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  void _needLogin(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('该功能需要登录'),
        action: SnackBarAction(
          label: '去登录',
          onPressed: () => Navigator.of(context).pushNamed('/login'),
        ),
      ),
    );
  }
}

/// 我的收藏：favoriteEpisodes() 单集列表。
class _FavoriteScreen extends StatefulWidget {
  const _FavoriteScreen();

  @override
  State<_FavoriteScreen> createState() => _FavoriteScreenState();
}

class _FavoriteScreenState extends State<_FavoriteScreen> {
  bool _loading = true;
  String? _error;
  List<Episode> _episodes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<XyzService>().favoriteEpisodes();
      if (!mounted) return;
      setState(() {
        _episodes = list;
        _loading = false;
      });
    } on XyzException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_episodes.isEmpty) {
      return const Center(child: Text('还没有收藏的单集'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _episodes.length,
        itemBuilder: (ctx, i) => EpisodeTile(
          episode: _episodes[i],
          episodes: _episodes,
          index: i,
        ),
      ),
    );
  }
}

/// 收听历史：playedHistory() 单集列表。
class _HistoryScreen extends StatefulWidget {
  const _HistoryScreen();

  @override
  State<_HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<_HistoryScreen> {
  bool _loading = true;
  String? _error;
  List<Episode> _episodes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<XyzService>().playedHistory();
      if (!mounted) return;
      setState(() {
        _episodes = list;
        _loading = false;
      });
    } on XyzException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _playAll() {
    if (_episodes.isEmpty) return;
    context.read<PlayerService>().playQueue(_episodes, 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('收听历史'),
        actions: [
          if (_episodes.isNotEmpty)
            IconButton(
              tooltip: '全部播放',
              icon: const Icon(Icons.play_arrow),
              onPressed: _playAll,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: const Text('重试')),
          ],
        ),
      ),
    }
    if (_episodes.isEmpty) {
      return const Center(child: Text('还没有收听历史'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _episodes.length,
        itemBuilder: (ctx, i) => EpisodeTile(
          episode: _episodes[i],
          episodes: _episodes,
          index: i,
        ),
      ),
    );
  }
}
