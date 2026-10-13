import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/xyz_service.dart';
import '../widgets/cover_image.dart';
import '../widgets/detail_scaffold.dart';

/// 单集评论页。路由参数为 Episode。
class CommentsScreen extends StatefulWidget {
  final Episode episode;

  const CommentsScreen({super.key, required this.episode});

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  bool _loading = true;
  String? _error;
  List<XyzComment> _comments = [];
  Map<String, dynamic>? _loadMoreKey;
  bool _loadingMore = false;
  String _order = 'HOT'; // HOT 最热 / TIME 最新
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
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
      _comments = [];
      _loadMoreKey = null;
    });
    try {
      final paged = await context
          .read<XyzService>()
          .comments(widget.episode.eid, order: _order);
      if (!mounted) return;
      setState(() {
        _comments = paged.items;
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
      final paged = await context.read<XyzService>().comments(
            widget.episode.eid,
            order: _order,
            loadMoreKey: _loadMoreKey,
          );
      if (!mounted) return;
      setState(() {
        _comments.addAll(paged.items);
        _loadMoreKey = paged.loadMoreKey;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _send() async {
    final content = _inputController.text.trim();
    if (content.isEmpty || _sending) return;
    if (!context.read<AuthService>().loggedIn) {
      Navigator.pushNamed(context, '/login');
      return;
    }
    setState(() => _sending = true);
    try {
      final comment = await context
          .read<XyzService>()
          .createComment(widget.episode.eid, content);
      if (!mounted) return;
      setState(() {
        _comments.insert(0, comment);
        _sending = false;
      });
      _inputController.clear();
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('评论已发表')));
    } on XyzException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('发表失败：$e')));
    }
  }

  Future<void> _toggleLike(XyzComment comment, int index) async {
    if (!context.read<AuthService>().loggedIn) {
      Navigator.pushNamed(context, '/login');
      return;
    }
    final target = !comment.isLiked;
    // 乐观更新
    setState(() {
      _comments[index] = XyzComment(
        id: comment.id,
        nickname: comment.nickname,
        avatar: comment.avatar,
        content: comment.content,
        likeCount: comment.likeCount + (target ? 1 : -1),
        replyCount: comment.replyCount,
        createdAt: comment.createdAt,
        isLiked: target,
      );
    });
    try {
      await context.read<XyzService>().likeComment(comment.id, target);
    } on XyzException catch (e) {
      if (!mounted) return;
      // 回滚
      setState(() => _comments[index] = comment);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _comments[index] = comment);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DetailScaffold(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '评论${widget.episode.commentCount > 0 ? '（${widget.episode.commentCount}）' : ''}',
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort),
              tooltip: '排序',
              onSelected: (v) {
                if (v != _order) {
                  setState(() => _order = v);
                  _load();
                }
              },
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: 'HOT',
                  checked: _order == 'HOT',
                  child: const Text('最热'),
                ),
                CheckedPopupMenuItem(
                  value: 'TIME',
                  checked: _order == 'TIME',
                  child: const Text('最新'),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(child: _buildList(theme)),
            _buildInputBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
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
    if (_comments.isEmpty) {
      return const Center(child: Text('还没有评论，来抢沙发吧'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _comments.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _comments.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _CommentTile(
            comment: _comments[i],
            onLike: () => _toggleLike(_comments[i], i),
          );
        },
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.surfaceContainerHighest,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                decoration: InputDecoration(
                  hintText: '写下你的评论…',
                  isDense: true,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final XyzComment comment;
  final VoidCallback onLike;

  const _CommentTile({required this.comment, required this.onLike});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoverImage(url: comment.avatar, size: 40, radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        comment.nickname.isEmpty ? '匿名用户' : comment.nickname,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (comment.createdAt.isNotEmpty)
                      Text(
                        _formatTime(comment.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.content,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(height: 1.5, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    InkWell(
                      onTap: onLike,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              comment.isLiked
                                  ? Icons.thumb_up
                                  : Icons.thumb_up_outlined,
                              size: 16,
                              color: comment.isLiked
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${comment.likeCount}',
                              style: TextStyle(
                                fontSize: 12,
                                color: comment.isLiked
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (comment.replyCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '${comment.replyCount} 条回复',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
