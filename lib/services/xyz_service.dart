import '../core/api.dart';
import '../models/models.dart';

/// 直连小宇宙官方 API（https://api.xiaoyuzhoufm.com）的业务接口封装。
/// 上游 path 与请求体照抄 ultrazg/xyz 项目 handlers 里抓到的官方请求
/// （`constant.BaseUrl + "/v1/xxx"` 的部分）。
/// 上游响应是直接 JSON（通常 `{data: <载荷>, loadMoreKey?}`），没有信封层，
/// 这里统一取 `resp['data']` 做载荷，`resp['loadMoreKey']` 做分页透传。
class XyzService {
  final XyzApiClient api;

  XyzService(this.api);

  // ------------------------------------------------------------------ 内部辅助

  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  static List<Map<String, dynamic>> _asMapList(dynamic v) {
    final out = <Map<String, dynamic>>[];
    if (v is List) {
      for (final e in v) {
        final m = _asMap(e);
        if (m != null) out.add(m);
      }
    }
    return out;
  }

  /// 上游响应的 data 载荷转数组。
  static List<Map<String, dynamic>> _dataList(Map<String, dynamic> resp) {
    return _asMapList(resp['data']);
  }

  /// 上游响应的 loadMoreKey 原样透传。形态各接口不同：
  /// 对象（如 {skip} / {pubDate,id,direction}）、字符串（如 discovery 的 "pick"）、数字。
  /// 为统一 Paged.loadMoreKey 的 Map 类型，字符串/数字包一层存，
  /// 发回上游时用 [_sendableLoadMoreKey] 还原。
  static Map<String, dynamic>? _loadMoreKey(Map<String, dynamic> resp) {
    final k = resp['loadMoreKey'];
    if (k is Map && k.isNotEmpty) return Map<String, dynamic>.from(k);
    if (k is String && k.isNotEmpty) return {'loadMoreKey': k};
    if (k is num) return {'loadMoreKey': k};
    return null;
  }

  /// 把 [_loadMoreKey] 存下来的值还原成上游要的形态发回去。
  static dynamic _sendableLoadMoreKey(Map<String, dynamic>? stored) {
    if (stored == null) return null;
    if (stored.length == 1 && stored.containsKey('loadMoreKey')) {
      return stored['loadMoreKey'];
    }
    return stored;
  }

  DiscoverySection _parseDiscoveryBlock(Map<String, dynamic> block) {
    final title = str(block['title']);
    final targetType = str(block['targetType']);
    final podcasts = <Podcast>[];
    final episodes = <Episode>[];
    final target = block['target'];
    if (target is List) {
      for (final t in target) {
        final tm = _asMap(t);
        if (tm == null) continue;
        final pm = _asMap(tm['podcast']);
        final em = _asMap(tm['episode']);
        if (targetType == 'PODCAST') {
          if (pm != null) podcasts.add(Podcast.fromJson(pm));
        } else if (targetType == 'EPISODE') {
          if (em != null) episodes.add(Episode.fromJson(em));
        } else {
          // targetType 缺失时按实际内容兜底
          if (pm != null) podcasts.add(Podcast.fromJson(pm));
          if (em != null) episodes.add(Episode.fromJson(em));
        }
      }
    }
    return DiscoverySection(
      title: title,
      targetType: targetType,
      podcasts: podcasts,
      episodes: episodes,
    );
  }

  // ------------------------------------------------------------------ 首页发现

  /// 首页发现板块。loadMoreKey 为上游约定的字符串：
  /// 不传查「大家都在听」+「编辑精选」；`mediumDiscoveryPictorial` 查榜单板块；
  /// `discoveryTopic` 查「为你精选的节目」往后；`pick` 查「TA 们的喜欢」等。
  Future<List<DiscoverySection>> discovery({String? loadMoreKey}) async {
    final resp = await api.post('/v1/discovery-feed/list', {
      'returnAll': 'false',
      if (loadMoreKey != null && loadMoreKey.isNotEmpty)
        'loadMoreKey': loadMoreKey,
    });
    final sections = <DiscoverySection>[];
    for (final e in _dataList(resp)) {
      // 元素：{type, data: [{title, targetType, target: [...]}]}；
      // 少数类型（如 NEW_POWER）的 data 是单个对象，用 items 承载节目。
      final data = e['data'];
      if (data is List) {
        for (final b in data) {
          final bm = _asMap(b);
          if (bm != null) sections.add(_parseDiscoveryBlock(bm));
        }
      } else if (data is Map) {
        final items = data['items'];
        if (items is List) {
          final podcasts = <Podcast>[];
          for (final it in items) {
            final im = _asMap(it);
            if (im != null && str(im['type']) == 'PODCAST') {
              podcasts.add(Podcast.fromJson(im));
            }
          }
          sections.add(DiscoverySection(
            title: str(data['title']),
            targetType: 'PODCAST',
            podcasts: podcasts,
          ));
        }
      }
    }
    return sections;
  }

  /// 刷新「大家都在听」推荐。返回上游 data 的 target 数组解开 episode 层后的单集。
  Future<List<Episode>> refreshEpisodeRecommend() async {
    final resp = await api.post(
        '/v1/discovery-collection/refresh-episode-recommend', {});
    final m = _asMap(resp['data']);
    if (m == null) return [];
    final episodes = <Episode>[];
    final target = m['target'];
    if (target is List) {
      for (final t in target) {
        final tm = _asMap(t);
        final em = tm == null ? null : _asMap(tm['episode']);
        if (em != null) episodes.add(Episode.fromJson(em));
      }
    }
    return episodes;
  }

  /// 榜单：依次拉取最热榜（HOT）、锋芒榜（ROCK）、新星榜（NEW）。
  /// 上游为 GET `/v1/top-list/get?category=...`，返回 {title, items: [{item: {…单集…}}]}。
  /// 单个榜单失败不影响其他榜单。
  Future<List<TopChart>> topList() async {
    const categories = {
      'HOT': 'HOT_EPISODES_IN_24_HOURS',
      'ROCK': 'SKYROCKET_EPISODES',
      'NEW': 'NEW_STAR_EPISODES',
    };
    final charts = <TopChart>[];
    for (final entry in categories.entries) {
      try {
        final resp = await api.get('/v1/top-list/get?category=${entry.value}');
        final m = _asMap(resp['data']);
        if (m == null) continue;
        final title = str(m['title']);
        final episodes = <Episode>[];
        final items = m['items'];
        if (items is List) {
          for (final it in items) {
            final im = _asMap(it);
            final em = im == null ? null : _asMap(im['item']);
            if (em != null) episodes.add(Episode.fromJson(em));
          }
        }
        charts.add(TopChart(
          title: title.isEmpty ? entry.key : title,
          episodes: episodes,
        ));
      } catch (_) {
        // 单个榜单失败不影响整体
      }
    }
    return charts;
  }

  // ------------------------------------------------------------------ 节目与单集

  /// 节目详情（GET `/v1/podcast/get?pid=`）。返回里可能含 subscriptionStatus /
  /// subscriptionStar 等字段。
  Future<Podcast> podcastDetail(String pid) async {
    final resp = await api.get('/v1/podcast/get?pid=$pid');
    final m = _asMap(resp['data']);
    if (m == null) throw XyzException('节目详情解析失败');
    return Podcast.fromJson(m);
  }

  /// 相关节目推荐。元素为 `{podcast: {...}}` 包一层，解开。
  Future<List<Podcast>> relatedPodcasts(String pid) async {
    final resp = await api.post('/v1/related-podcast/list', {
      'pid': pid,
      'position': 'BOTTOM',
    });
    final list = <Podcast>[];
    for (final e in _dataList(resp)) {
      final pm = _asMap(e['podcast']) ?? e;
      list.add(Podcast.fromJson(pm));
    }
    return list;
  }

  /// 节目内「最受欢迎」单集列表。元素字段平铺。
  Future<List<Episode>> popularEpisodes(String pid) async {
    final resp = await api.post(
      '/v1/episode/list-by-filter',
      {'pid': pid, 'label': 'POPULAR'},
      '{}',
    );
    return _dataList(resp).map(Episode.fromJson).toList();
  }

  /// 节目单集列表。order: 'desc' 从新到旧 / 'asc' 从旧到新。
  /// loadMoreKey 从上次返回的 Paged.loadMoreKey 原样传入。
  Future<Paged<Episode>> episodeList(
    String pid, {
    String order = 'desc',
    Map<String, dynamic>? loadMoreKey,
  }) async {
    final resp = await api.post('/v1/episode/list', {
      'limit': '20',
      'pid': pid,
      'order': order,
      if (loadMoreKey != null)
        'loadMoreKey': _sendableLoadMoreKey(loadMoreKey),
    });
    return Paged<Episode>(
      items: _dataList(resp).map(Episode.fromJson).toList(),
      loadMoreKey: _loadMoreKey(resp),
    );
  }

  /// 单集详情（GET `/v1/episode/get?eid=`，含 media.url）。
  Future<Episode> episodeDetail(String eid) async {
    final resp = await api.get('/v1/episode/get?eid=$eid');
    final m = _asMap(resp['data']);
    if (m == null) throw XyzException('单集详情解析失败');
    return Episode.fromJson(m);
  }

  /// 付费单集音频链接（GET `/v1/private-media/get?dubbing=false&eid=`）。
  Future<String> privateMediaUrl(String eid) async {
    final resp = await api.get('/v1/private-media/get?dubbing=false&eid=$eid');
    final m = _asMap(resp['data']);
    final url = str(m?['url']);
    if (url.isEmpty) throw XyzException('未获取到付费单集音频链接');
    return url;
  }

  // ------------------------------------------------------------------ 搜索

  /// 搜索。type: ALL / PODCAST / EPISODE / USER（小写传入也行，内部转大写）。
  /// ALL 时返回里混有 HEADER / FOOTER 等占位元素，已过滤；
  /// 用户结果在 `{type: "SEARCHED_USERS", users: [...]}` 里。
  Future<SearchResult> search(
    String keyword,
    String type, {
    Map<String, dynamic>? loadMoreKey,
  }) async {
    final resp = await api.post('/v1/search/create', {
      'limit': '20',
      'sourcePageName': '4',
      'type': type.toUpperCase(),
      'currentPageName': '4',
      'keyword': keyword,
      if (loadMoreKey != null)
        'loadMoreKey': _sendableLoadMoreKey(loadMoreKey),
    });
    final podcasts = <Podcast>[];
    final episodes = <Episode>[];
    final users = <XyzUserProfile>[];
    for (final e in _dataList(resp)) {
      switch (str(e['type'])) {
        case 'PODCAST':
          podcasts.add(Podcast.fromJson(e));
          break;
        case 'EPISODE':
          episodes.add(Episode.fromJson(e));
          break;
        case 'SEARCHED_USERS':
          final us = e['users'];
          if (us is List) {
            for (final u in us) {
              final um = _asMap(u);
              if (um != null) users.add(XyzUserProfile.fromJson(um));
            }
          }
          break;
      }
    }
    return SearchResult(
      podcasts: podcasts,
      episodes: episodes,
      users: users,
      loadMoreKey: _loadMoreKey(resp),
    );
  }

  /// 搜索框「你可能想搜的内容」预设词（GET `/v1/search/get-preset`）。
  Future<List<String>> searchPreset() async {
    final resp = await api.get('/v1/search/get-preset');
    final out = <String>[];
    for (final e in _dataList(resp)) {
      final t = str(e['text']);
      if (t.isNotEmpty) out.add(t);
    }
    return out;
  }

  // ------------------------------------------------------------------ 订阅

  /// 我的订阅。loadMoreKey 形态为 {skip}，从上次返回的 Paged.loadMoreKey 原样传入。
  /// 返回元素可能是 `{podcast: {...}}` 包一层，解开。
  Future<Paged<Podcast>> subscriptions({int skip = 0}) async {
    final resp = await api.post('/v1/subscription/list', {
      'limit': '20',
      'sortOrder': 'desc',
      'sortBy': 'subscribedAt',
      if (skip > 0) 'loadMoreKey': {'skip': skip},
    });
    final list = <Podcast>[];
    for (final e in _dataList(resp)) {
      final pm = _asMap(e['podcast']) ?? e;
      list.add(Podcast.fromJson(pm));
    }
    return Paged<Podcast>(
      items: list,
      loadMoreKey: _loadMoreKey(resp),
    );
  }

  /// 订阅 / 取消订阅节目。
  Future<void> updateSubscription(String pid, bool subscribe) async {
    await api.post(
      '/v1/subscription/update',
      {'pid': pid, 'mode': subscribe ? 'ON' : 'OFF'},
      '{}',
    );
  }

  /// 星标订阅列表。
  Future<List<Podcast>> starredSubscriptions() async {
    final resp = await api.post('/v1/subscription-star/list', {});
    return _dataList(resp).map(Podcast.fromJson).toList();
  }

  /// 未加星标的订阅列表。
  Future<List<Podcast>> nonStarredSubscriptions() async {
    final resp = await api.post('/v1/subscription/list-non-starred', {});
    return _dataList(resp).map(Podcast.fromJson).toList();
  }

  /// 更新星标订阅。
  Future<void> updateStarSubscription(String pid, bool star) async {
    await api.post('/v1/subscription-star/update', {
      'pid': pid,
      'withStar': star,
    });
  }

  // ------------------------------------------------------------------ 播放进度与收藏

  /// 批量查询单集播放进度。返回 eid -> 已播放进度（毫秒）。
  /// 注意：上游返回的 progress 单位是**秒**，这里统一转毫秒。
  Future<Map<String, double>> playProgress(List<String> eids) async {
    if (eids.isEmpty) return {};
    final resp = await api.post('/v1/playback-progress/list', {'eids': eids});
    final out = <String, double>{};
    for (final e in _dataList(resp)) {
      final eid = str(e['eid']);
      if (eid.isEmpty) continue;
      out[eid] = doubleOf(e['progress']) * 1000;
    }
    return out;
  }

  /// 上报单集播放进度。playedAt 用 ISO8601 UTC 时间；progress 按上游约定传秒。
  Future<void> updatePlayProgress({
    required String pid,
    required String eid,
    required int progressMs,
  }) async {
    await api.post('/v1/playback-progress/update', {
      'data': [
        {
          'pid': pid,
          'eid': eid,
          'progress': (progressMs / 1000).round(),
          'playedAt': DateTime.now().toUtc().toIso8601String(),
        },
      ],
    });
  }

  /// 已收藏的单集列表。
  Future<List<Episode>> favoriteEpisodes() async {
    final resp = await api.post('/v1/favorite/list', {}, '{}');
    return _dataList(resp).map(Episode.fromJson).toList();
  }

  /// 收藏 / 取消收藏单集。
  Future<void> updateFavorite(String eid, bool favorite) async {
    await api.post('/v1/favorite/update', {
      'eid': eid,
      'favorited': favorite,
      'sourcePageName': 8,
      'currentPageName': 9,
    });
  }

  /// 收听历史。元素为 `{episode: {...}, recentAudiences: [...]}` 包一层，解开。
  Future<List<Episode>> playedHistory() async {
    final resp = await api.post('/v1/episode-played/list-history', {});
    final list = <Episode>[];
    for (final e in _dataList(resp)) {
      final em = _asMap(e['episode']) ?? e;
      list.add(Episode.fromJson(em));
    }
    return list;
  }

  /// 订阅更新（收件箱）。元素字段平铺，个别可能包 episode 层，兼容。
  Future<List<Episode>> inboxList() async {
    final resp = await api.post('/v1/inbox/list', {'limit': '20'});
    final list = <Episode>[];
    for (final e in _dataList(resp)) {
      final em = _asMap(e['episode']) ?? e;
      list.add(Episode.fromJson(em));
    }
    return list;
  }

  // ------------------------------------------------------------------ 评论与时间点

  /// 单集评论。order: HOT 全部评论 / TIME 最新评论 / TIMESTAMP 时点评论。
  Future<Paged<XyzComment>> comments(
    String eid, {
    String order = 'HOT',
    Map<String, dynamic>? loadMoreKey,
  }) async {
    final resp = await api.post('/v1/comment/list-primary', {
      'order': order,
      'owner': {'id': eid, 'type': 'EPISODE'},
      if (loadMoreKey != null)
        'loadMoreKey': _sendableLoadMoreKey(loadMoreKey),
    });
    return Paged<XyzComment>(
      items: _dataList(resp).map(XyzComment.fromJson).toList(),
      loadMoreKey: _loadMoreKey(resp),
    );
  }

  /// 发表评论（replyToCommentId 非空时为回复他人评论）。
  /// 注意上游请求体是 `{"text", "owner": {"id", "type"}}` 形态。
  Future<XyzComment> createComment(
    String eid,
    String content, {
    String? replyToCommentId,
  }) async {
    final resp = await api.post(
      '/v1/comment/create',
      {
        'text': content,
        'owner': {'id': eid, 'type': 'EPISODE'},
        if (replyToCommentId != null && replyToCommentId.isNotEmpty)
          'replyToCommentId': replyToCommentId,
      },
      '{}',
    );
    final m = _asMap(resp['data']);
    if (m == null) throw XyzException('评论发表失败');
    return XyzComment.fromJson(m);
  }

  /// 点赞 / 取消点赞评论。上游请求体为 `{"liked", "target": {"id", "type"}}` 形态。
  Future<void> likeComment(String commentId, bool like) async {
    await api.post('/v1/like/update', {
      'liked': like,
      'target': {'id': commentId, 'type': 'COMMENT'},
    });
  }

  /// 精彩时间点。接口需要 duration（秒）；
  /// 上游返回 episodeClaps 数组（下标对应时间线分段，count 为标记数），
  /// 这里按分段均匀换算出每段的起始毫秒时间。
  Future<List<ClapPoint>> claps(String eid, {int? duration}) async {
    final resp = await api.post('/v1/clap/list', {
      'eid': eid,
      'duration': duration ?? 0,
    });
    final m = _asMap(resp['data']);
    if (m == null) return [];
    final points = <ClapPoint>[];
    final arr = m['episodeClaps'];
    final durationMs = (duration ?? 0) * 1000;
    if (arr is List && arr.isNotEmpty) {
      final n = arr.length;
      for (var i = 0; i < n; i++) {
        final cm = _asMap(arr[i]);
        final count = intOf(cm?['count']);
        final positionMs = durationMs > 0 ? (i * durationMs / n).round() : 0;
        points.add(ClapPoint(
          positionMs: positionMs,
          content: '$count 人标记',
        ));
      }
    }
    return points;
  }

  // ------------------------------------------------------------------ 分类

  /// 全部分类。
  Future<List<Category>> categories() async {
    final resp = await api.post('/v1/category/list-all', {});
    return _dataList(resp).map(Category.fromJson).toList();
  }

  /// 分类下的标签页。
  Future<List<CategoryTab>> categoryTabs(String categoryId) async {
    final resp = await api.post('/v1/category/podcast/list-tabs', {
      'categoryId': categoryId,
    });
    return _dataList(resp).map(CategoryTab.fromJson).toList();
  }

  /// 分类标签下的节目列表。
  /// 注意：上游接口同时需要 categoryId 和 tab；这里 tabId 为标签 id，
  /// categoryId 通过可选命名参数传入。上游的 loadMoreKey 是数字形态。
  Future<Paged<Podcast>> categoryPodcasts(
    String tabId, {
    String? categoryId,
    Map<String, dynamic>? loadMoreKey,
  }) async {
    final body = <String, dynamic>{
      'tab': tabId,
      'omitSubscribed': false,
    };
    if (categoryId != null && categoryId.isNotEmpty) {
      body['categoryId'] = categoryId;
    }
    if (loadMoreKey != null) {
      body['loadMoreKey'] = _sendableLoadMoreKey(loadMoreKey);
    }
    final resp = await api.post('/v1/category/podcast/list-by-tab', body);
    final list = <Podcast>[];
    for (final e in _dataList(resp)) {
      final pm = _asMap(e['podcast']) ?? e;
      list.add(Podcast.fromJson(pm));
    }
    return Paged<Podcast>(
      items: list,
      loadMoreKey: _loadMoreKey(resp),
    );
  }

  // ------------------------------------------------------------------ 用户

  /// 当前登录用户的资料（GET `/v1/profile/get`，靠 token 识别）。
  Future<XyzUserProfile> myProfile() async {
    final resp = await api.get('/v1/profile/get');
    final m = _asMap(resp['data']);
    if (m == null) throw XyzException('获取用户信息失败');
    return XyzUserProfile.fromJson(m);
  }
}
