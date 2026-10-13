import '../core/utils.dart';

/// 小宇宙 API 的 JSON 形态很松散（字段缺失是常态），以下辅助统一做防御性取值。
/// intOf / httpsUrl 复用 core/utils.dart；这里补充 str / doubleOf / picUrl。
String str(dynamic v) {
  if (v == null) return '';
  if (v is String) return v;
  return v.toString();
}

double doubleOf(dynamic v) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

/// 取图片 URL，处理三种形态：
/// 1. `{picUrl, largePicUrl, ...}` —— 直接取 picUrl（无则 largePicUrl/middlePicUrl）；
/// 2. `{picture: {picUrl, ...}}` —— 递归解开 picture 层；
/// 3. 纯字符串 —— 直接返回。
/// 返回的 URL 统一转 https。
String picUrl(dynamic img) {
  if (img == null) return '';
  if (img is String) return httpsUrl(img);
  if (img is Map) {
    if (img['picture'] != null) return picUrl(img['picture']);
    final p = img['picUrl'];
    if (p is String && p.isNotEmpty) return httpsUrl(p);
    final l = img['largePicUrl'];
    if (l is String && l.isNotEmpty) return httpsUrl(l);
    final m = img['middlePicUrl'];
    if (m is String && m.isNotEmpty) return httpsUrl(m);
  }
  return '';
}

/// duration 可能是秒或毫秒：值 < 100000 视为秒，转毫秒；否则视为毫秒。
int _durationMs(dynamic v) {
  final n = doubleOf(v);
  if (n <= 0) return 0;
  return n < 100000 ? (n * 1000).round() : n.round();
}

/// 播客节目。
class Podcast {
  final String pid;
  final String title;
  final String brief;
  final String description;
  final String image;
  final String author;
  final int episodeCount;
  final int subscriptionCount;
  final bool isSubscribed; // subscriptionStatus == 'ON'
  final bool isStarred; // subscriptionStar == true
  final String payType;
  final String colorHex; // color.original
  final DateTime? latestEpisodePubDate;

  const Podcast({
    this.pid = '',
    this.title = '',
    this.brief = '',
    this.description = '',
    this.image = '',
    this.author = '',
    this.episodeCount = 0,
    this.subscriptionCount = 0,
    this.isSubscribed = false,
    this.isStarred = false,
    this.payType = '',
    this.colorHex = '',
    this.latestEpisodePubDate,
  });

  factory Podcast.fromJson(Map<String, dynamic> json) {
    final color = json['color'];
    String colorHex = '';
    if (color is Map) {
      colorHex = str(color['original']);
      if (colorHex.isEmpty) colorHex = str(color['light']);
    }
    DateTime? latestPub;
    final lp = str(json['latestEpisodePubDate']);
    if (lp.isNotEmpty) latestPub = DateTime.tryParse(lp);
    return Podcast(
      pid: str(json['pid']),
      title: str(json['title']),
      brief: str(json['brief']),
      description: str(json['description']),
      image: picUrl(json['image']),
      author: str(json['author']),
      episodeCount: intOf(json['episodeCount']),
      subscriptionCount: intOf(json['subscriptionCount']),
      isSubscribed: str(json['subscriptionStatus']) == 'ON',
      isStarred: json['subscriptionStar'] == true,
      payType: str(json['payType']),
      colorHex: colorHex,
      latestEpisodePubDate: latestPub,
    );
  }
}

/// 播客单集。注意：fromJson 只处理字段平铺形态（episodeList 等返回的 `{type: "EPISODE", ...}`）；
/// discovery / playedHistory 等返回的 `{episode: {...}}` 包一层形态由调用方先解开。
class Episode {
  final String eid;
  final String title;
  final String description;
  final String shownotes;
  final String audioUrl; // media.source.url（付费单集可能为空）
  final int durationMs;
  final String pubDate;
  final String image; // 单集自身的封面（部分列表接口返回）
  final String podcastPid;
  final String podcastTitle;
  final String podcastImage;
  final String podcastAuthor;
  final double progressMs; // 播放进度（毫秒）
  final bool isFavorite;
  final bool isFinished;
  final bool isPrivateMedia;
  final int clapCount;
  final int commentCount;
  final int favoriteCount;

  /// 列表封面：优先播客封面，回退单集自身封面。
  String get coverUrl => podcastImage.isNotEmpty ? podcastImage : image;

  const Episode({
    this.eid = '',
    this.title = '',
    this.description = '',
    this.shownotes = '',
    this.audioUrl = '',
    this.durationMs = 0,
    this.pubDate = '',
    this.image = '',
    this.podcastPid = '',
    this.podcastTitle = '',
    this.podcastImage = '',
    this.podcastAuthor = '',
    this.progressMs = 0,
    this.isFavorite = false,
    this.isFinished = false,
    this.isPrivateMedia = false,
    this.clapCount = 0,
    this.commentCount = 0,
    this.favoriteCount = 0,
  });

  Duration get duration => Duration(milliseconds: durationMs);

  /// pubDate（ISO8601）格式化为 yyyy-MM-dd；解析失败时原样返回。
  String get displayDate {
    if (pubDate.isEmpty) return '';
    final dt = DateTime.tryParse(pubDate);
    if (dt == null) return pubDate;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  factory Episode.fromJson(Map<String, dynamic> json) {
    String audioUrl = '';
    final media = json['media'];
    if (media is Map) {
      final source = media['source'];
      if (source is Map && source['url'] is String) {
        audioUrl = source['url'] as String;
      } else if (media['url'] is String) {
        audioUrl = media['url'] as String;
      }
    }
    if (audioUrl.isEmpty) {
      final enclosure = json['enclosure'];
      if (enclosure is Map && enclosure['url'] is String) {
        audioUrl = enclosure['url'] as String;
      }
    }
    String podcastPid = str(json['pid']);
    String podcastTitle = '';
    String podcastImage = '';
    String podcastAuthor = '';
    final pod = json['podcast'];
    if (pod is Map) {
      final innerPid = str(pod['pid']);
      if (innerPid.isNotEmpty) podcastPid = innerPid;
      podcastTitle = str(pod['title']);
      podcastImage = picUrl(pod['image']);
      podcastAuthor = str(pod['author']);
    }
    return Episode(
      eid: str(json['eid']),
      title: str(json['title']),
      description: str(json['description']),
      shownotes: str(json['shownotes']),
      audioUrl: httpsUrl(audioUrl),
      durationMs: _durationMs(json['duration']),
      pubDate: str(json['pubDate']),
      image: picUrl(json['image']),
      podcastPid: podcastPid,
      podcastTitle: podcastTitle,
      podcastImage: podcastImage,
      podcastAuthor: podcastAuthor,
      progressMs: doubleOf(json['progress']),
      isFavorite: json['isFavorited'] == true || json['isFavorite'] == true,
      isFinished: json['isFinished'] == true,
      isPrivateMedia: json['isPrivateMedia'] == true,
      clapCount: intOf(json['clapCount']),
      commentCount: intOf(json['commentCount']),
      favoriteCount: intOf(json['favoriteCount']),
    );
  }
}

/// 首页发现板块（如「大家都在听」「编辑精选」）。
class DiscoverySection {
  final String title;
  final String targetType; // PODCAST / EPISODE
  final List<Podcast> podcasts;
  final List<Episode> episodes;

  const DiscoverySection({
    this.title = '',
    this.targetType = '',
    this.podcasts = const [],
    this.episodes = const [],
  });
}

/// 评论。
class XyzComment {
  final String id;
  final String nickname;
  final String avatar;
  final String content;
  final int likeCount;
  final int replyCount;
  final String createdAt;
  final bool isLiked;

  const XyzComment({
    this.id = '',
    this.nickname = '',
    this.avatar = '',
    this.content = '',
    this.likeCount = 0,
    this.replyCount = 0,
    this.createdAt = '',
    this.isLiked = false,
  });

  factory XyzComment.fromJson(Map<String, dynamic> json) {
    String nickname = '';
    String avatar = '';
    final author = json['author'];
    if (author is Map) {
      nickname = str(author['nickname']);
      avatar = picUrl(author['avatar']);
    }
    return XyzComment(
      id: str(json['id']),
      nickname: nickname,
      avatar: avatar,
      content: str(json['text']),
      likeCount: intOf(json['likeCount']),
      replyCount: intOf(json['threadReplyCount'] ?? json['replyCount']),
      createdAt: str(json['createdAt']),
      isLiked: json['liked'] == true,
    );
  }
}

/// 播客分类。
class Category {
  final String id;
  final String name;
  final String image;

  const Category({this.id = '', this.name = '', this.image = ''});

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: str(json['id']),
      name: str(json['name']),
      image: picUrl(json['icon']),
    );
  }
}

/// 分类下的标签页。
class CategoryTab {
  final String id;
  final String name;

  const CategoryTab({this.id = '', this.name = ''});

  factory CategoryTab.fromJson(Map<String, dynamic> json) {
    return CategoryTab(id: str(json['id']), name: str(json['name']));
  }
}

/// 分页结果：loadMoreKey 原样透传（形态各接口不同：对象/字符串/数字都可能）。
class Paged<T> {
  final List<T> items;
  final Map<String, dynamic>? loadMoreKey;

  const Paged({required this.items, this.loadMoreKey});

  bool get hasMore => loadMoreKey != null && loadMoreKey!.isNotEmpty;
}

/// 用户资料。
class XyzUserProfile {
  final String uid;
  final String nickname;
  final String bio;
  final String avatar;

  const XyzUserProfile({
    this.uid = '',
    this.nickname = '',
    this.bio = '',
    this.avatar = '',
  });

  factory XyzUserProfile.fromJson(Map<String, dynamic> json) {
    return XyzUserProfile(
      uid: str(json['uid']),
      nickname: str(json['nickname']),
      bio: str(json['bio']),
      avatar: picUrl(json['avatar']),
    );
  }
}

/// 搜索结果。
class SearchResult {
  final List<Podcast> podcasts;
  final List<Episode> episodes;
  final List<XyzUserProfile> users;
  final Map<String, dynamic>? loadMoreKey;

  const SearchResult({
    this.podcasts = const [],
    this.episodes = const [],
    this.users = const [],
    this.loadMoreKey,
  });
}

/// 榜单（如最热榜/锋芒榜/新星榜）。
class TopChart {
  final String title;
  final List<Episode> episodes;

  const TopChart({this.title = '', this.episodes = const []});
}

/// 精彩时间点：positionMs 为该分段起始时间（毫秒）。
class ClapPoint {
  final int positionMs;
  final String content;

  const ClapPoint({this.positionMs = 0, this.content = ''});
}

/// 编辑精选：单集 + 编辑评语。
class EditorPick {
  final Episode episode;
  final String comment;

  const EditorPick({required this.episode, this.comment = ''});
}
