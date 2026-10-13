import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../models/models.dart';
import '../services/xyz_service.dart';
import '../widgets/detail_scaffold.dart';
import '../widgets/episode_tile.dart';

/// 榜单详情页。路由参数：{'title': String, 'category': 'HOT'/'ROCK'/'NEW'}。
///
/// topList() 按 HOT、ROCK、NEW 顺序返回，先按标题匹配，匹配不上再按顺序兜底。
class ChartScreen extends StatefulWidget {
  final String title;
  final String category;

  const ChartScreen({super.key, required this.title, required this.category});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  bool _loading = true;
  String? _error;
  List<Episode> _episodes = [];

  static const _order = ['HOT', 'ROCK', 'NEW'];

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
      final charts = await context.read<XyzService>().topList();
      if (!mounted) return;
      TopChart? hit;
      for (final c in charts) {
        if (c.title == widget.title) {
          hit = c;
          break;
        }
      }
      hit ??= () {
        final idx = _order.indexOf(widget.category);
        if (idx >= 0 && idx < charts.length) return charts[idx];
        return charts.isNotEmpty ? charts.first : null;
      }();
      setState(() {
        _episodes = hit?.episodes ?? [];
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
    return DetailScaffold(
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: _buildBody(),
      ),
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
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_episodes.isEmpty) {
      return const Center(child: Text('暂无数据'));
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
