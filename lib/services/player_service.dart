import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'xyz_service.dart';

enum PlayMode { sequence, loop, single, shuffle }

/// 播客播放器：单集队列、播放模式、倍速、播放进度云同步。
///
/// - 播放 URL 解析：列表里拿到的 Episode 可能没有 audioUrl，
///   此时调 episodeDetail 取；付费单集（isPrivateMedia）调 privateMediaUrl（需登录）。
/// - 播放进度：开始播放时拉取云端进度并续播；播放中每 15 秒、
///   暂停/切歌时上报云端（未登录或失败时静默跳过）。
/// - 取不到 URL 的单集自动跳过，一轮都播不了时给出提示。
class PlayerService extends ChangeNotifier {
  final XyzService xyz;
  final AudioPlayer _player = AudioPlayer();
  final Random _random = Random();

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration? _duration;

  List<Episode> queue = [];
  int index = -1;
  PlayMode mode = PlayMode.loop;

  double _speed = 1.0;
  double get speed => _speed;

  String? errorMessage;

  final Set<String> _failed = {};
  final Map<String, Episode> _resolved = {}; // eid -> 补全了 audioUrl 的 Episode
  bool _busy = false;

  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);

  PlayerService(this.xyz) {
    _player.onPlayerStateChanged.listen((state) {
      final wasPlaying = _playing;
      _playing = state == PlayerState.playing;
      if (wasPlaying && !_playing) {
        // 暂停时上报一次进度
        _syncProgress();
      }
      notifyListeners();
    });
    _player.onPlayerComplete.listen((_) => _onCompleted());
    _player.onDurationChanged.listen((d) {
      _duration = d;
      notifyListeners();
    });
    _player.onPositionChanged.listen((pos) {
      _position = pos;
      // 播放中每 15 秒上报一次进度
      if (_playing &&
          DateTime.now().difference(_lastSync).inSeconds >= 15) {
        _syncProgress();
      }
      notifyListeners();
    });
    _loadSpeed();
  }

  Future<void> _loadSpeed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getDouble('play_speed') ?? 1.0;
      if (s >= 0.5 && s <= 3.0) {
        _speed = s;
        await _player.setPlaybackRate(s);
        notifyListeners();
      }
    } catch (_) {}
  }

  Episode? get current {
    final e = (index >= 0 && index < queue.length) ? queue[index] : null;
    if (e == null) return null;
    return _resolved[e.eid] ?? e;
  }

  bool get hasQueue => queue.isNotEmpty;
  bool get playing => _playing;
  Duration get position => _position;
  Duration? get duration => _duration;
  Stream<Duration> get positionStream => _player.onPositionChanged;

  String get modeLabel => switch (mode) {
        PlayMode.sequence => '顺序播放',
        PlayMode.loop => '列表循环',
        PlayMode.single => '单集循环',
        PlayMode.shuffle => '随机播放',
      };

  // ---------- 队列控制 ----------

  Future<void> playQueue(List<Episode> episodes, int startIndex) async {
    if (episodes.isEmpty) return;
    queue = List.of(episodes);
    _failed.clear();
    await _playAt(startIndex.clamp(0, queue.length - 1));
  }

  /// 单集快捷播放：把该单集作为独立队列播放。
  Future<void> playEpisode(Episode e) => playQueue([e], 0);

  Future<void> jumpTo(int i) async {
    if (i < 0 || i >= queue.length) return;
    await _playAt(i);
  }

  /// 下一首播放：插到当前单集后面
  Future<void> playNext(Episode episode) async {
    if (queue.isEmpty) {
      await playQueue([episode], 0);
      return;
    }
    queue.insert(index + 1, episode);
    notifyListeners();
  }

  void removeAt(int i) {
    if (i < 0 || i >= queue.length) return;
    queue.removeAt(i);
    if (i == index) {
      if (queue.isEmpty) {
        index = -1;
        _player.stop();
      } else {
        _playAt(i % queue.length);
      }
    } else if (i < index) {
      index--;
    }
    notifyListeners();
  }

  void clearQueue() {
    queue = [];
    index = -1;
    _player.stop();
    notifyListeners();
  }

  // ---------- 播放实现 ----------

  Future<void> _playAt(int i) async {
    if (queue.isEmpty || _busy) return;
    _busy = true;
    errorMessage = null;
    try {
      int n = i;
      int attempts = 0;
      while (attempts < queue.length) {
        final raw = queue[n];
        if (_failed.contains(raw.eid)) {
          n = _nextIndex(n);
          attempts++;
          continue;
        }
        index = n;
        notifyListeners();

        final ep = await _resolveEpisode(raw);
        if (ep == null) {
          _failed.add(raw.eid);
          errorMessage = '《${raw.title}》暂无可播放的音频，已跳过';
          notifyListeners();
          n = _nextIndex(n);
          attempts++;
          continue;
        }
        try {
          await _player.setPlaybackRate(_speed);
          await _player.play(UrlSource(ep.audioUrl));
          errorMessage = null;
          notifyListeners();
          // 恢复云端播放进度
          _restoreProgress(ep);
          // 上报收听历史（失败静默）
          _reportPlayed(ep.eid);
          _prefetchNext(n);
          return;
        } catch (e) {
          _failed.add(raw.eid);
          errorMessage = '《${raw.title}》播放器加载失败：$e';
          notifyListeners();
        }
        n = _nextIndex(n);
        attempts++;
      }
      errorMessage = '队列中没有可播放的单集';
      notifyListeners();
    } finally {
      _busy = false;
    }
  }

  /// 解析出可播放的 Episode（含 audioUrl），解析失败返回 null。
  Future<Episode?> _resolveEpisode(Episode raw) async {
    final cached = _resolved[raw.eid];
    if (cached != null && cached.audioUrl.isNotEmpty) return cached;
    if (raw.audioUrl.isNotEmpty) {
      _resolved[raw.eid] = raw;
      return raw;
    }
    try {
      final detail = await xyz.episodeDetail(raw.eid);
      if (detail.audioUrl.isNotEmpty) {
        _resolved[raw.eid] = _mergeEpisode(raw, detail);
        return _resolved[raw.eid];
      }
      // 付费单集：尝试取付费音频链接（需登录）
      if (detail.isPrivateMedia || raw.isPrivateMedia) {
        final url = await xyz.privateMediaUrl(raw.eid);
        if (url.isNotEmpty) {
          _resolved[raw.eid] = _withUrl(_mergeEpisode(raw, detail), url);
          return _resolved[raw.eid];
        }
      }
    } catch (_) {}
    return null;
  }

  /// 把详情接口返回的字段合并到列表版 Episode（保留列表里的 podcast 信息等）。
  Episode _mergeEpisode(Episode base, Episode detail) {
    return Episode(
      eid: base.eid,
      title: base.title.isNotEmpty ? base.title : detail.title,
      description:
          detail.description.isNotEmpty ? detail.description : base.description,
      shownotes: detail.shownotes.isNotEmpty ? detail.shownotes : base.shownotes,
      audioUrl: detail.audioUrl,
      durationMs: detail.durationMs > 0 ? detail.durationMs : base.durationMs,
      pubDate: base.pubDate.isNotEmpty ? base.pubDate : detail.pubDate,
      podcastPid: base.podcastPid.isNotEmpty ? base.podcastPid : detail.podcastPid,
      podcastTitle:
          base.podcastTitle.isNotEmpty ? base.podcastTitle : detail.podcastTitle,
      podcastImage:
          base.podcastImage.isNotEmpty ? base.podcastImage : detail.podcastImage,
      podcastAuthor: base.podcastAuthor.isNotEmpty
          ? base.podcastAuthor
          : detail.podcastAuthor,
      progressMs: base.progressMs,
      isFavorite: detail.isFavorite || base.isFavorite,
      isFinished: detail.isFinished || base.isFinished,
      isPrivateMedia: detail.isPrivateMedia || base.isPrivateMedia,
      clapCount: detail.clapCount > 0 ? detail.clapCount : base.clapCount,
      commentCount:
          detail.commentCount > 0 ? detail.commentCount : base.commentCount,
      favoriteCount:
          detail.favoriteCount > 0 ? detail.favoriteCount : base.favoriteCount,
    );
  }

  Episode _withUrl(Episode e, String url) {
    return Episode(
      eid: e.eid,
      title: e.title,
      description: e.description,
      shownotes: e.shownotes,
      audioUrl: url,
      durationMs: e.durationMs,
      pubDate: e.pubDate,
      podcastPid: e.podcastPid,
      podcastTitle: e.podcastTitle,
      podcastImage: e.podcastImage,
      podcastAuthor: e.podcastAuthor,
      progressMs: e.progressMs,
      isFavorite: e.isFavorite,
      isFinished: e.isFinished,
      isPrivateMedia: e.isPrivateMedia,
      clapCount: e.clapCount,
      commentCount: e.commentCount,
      favoriteCount: e.favoriteCount,
    );
  }

  /// 后台预解析下一首的播放 URL，切歌时更快
  void _prefetchNext(int currentIndex) {
    if (queue.isEmpty) return;
    final nextIdx = _nextIndex(currentIndex);
    if (nextIdx == currentIndex) return;
    final ep = queue[nextIdx];
    if (_failed.contains(ep.eid)) return;
    final cached = _resolved[ep.eid];
    if (cached != null && cached.audioUrl.isNotEmpty) return;
    _resolveEpisode(ep).catchError((_) => null);
  }

  /// 上报单集已播放到收听历史（失败静默，不阻塞播放）。
  void _reportPlayed(String eid) {
    if (!xyz.api.hasToken) return;
    xyz.reportPlayed(eid).catchError((_) => null);
  }

  // ---------- 播放进度云同步 ----------

  /// 开始播放后：拉取云端进度，断点续播（大于 5 秒且未接近结尾时 seek）。
  Future<void> _restoreProgress(Episode ep) async {
    if (!xyz.api.hasToken) return;
    try {
      final map = await xyz.playProgress([ep.eid]);
      final ms = map[ep.eid] ?? 0;
      if (ms > 5000) {
        final dur = _duration?.inMilliseconds ?? ep.durationMs;
        if (dur <= 0 || ms < dur - 10000) {
          await _player.seek(Duration(milliseconds: ms.round()));
        }
      }
    } catch (_) {}
  }

  /// 上报当前播放进度到云端（失败静默）。
  Future<void> _syncProgress() async {
    final ep = current;
    if (ep == null || ep.podcastPid.isEmpty || !xyz.api.hasToken) return;
    _lastSync = DateTime.now();
    try {
      await xyz.updatePlayProgress(
        pid: ep.podcastPid,
        eid: ep.eid,
        progressMs: _position.inMilliseconds,
      );
    } catch (_) {}
  }

  int _nextIndex(int from) {
    if (queue.isEmpty) return 0;
    if (mode == PlayMode.shuffle) return _random.nextInt(queue.length);
    final n = from + 1;
    return n >= queue.length ? 0 : n;
  }

  int _prevIndex(int from) {
    if (queue.isEmpty) return 0;
    if (mode == PlayMode.shuffle) return _random.nextInt(queue.length);
    final n = from - 1;
    return n < 0 ? queue.length - 1 : n;
  }

  Future<void> _onCompleted() async {
    if (mode == PlayMode.single && current != null) {
      await _player.seek(Duration.zero);
      await _player.resume();
    } else if (mode == PlayMode.sequence &&
        index >= 0 &&
        index == queue.length - 1) {
      // 顺序播放到最后一首：停住
      await _player.stop();
    } else {
      await next();
    }
  }

  // ---------- 播放控制 ----------

  Future<void> toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      if (index < 0 && queue.isNotEmpty) {
        await _playAt(0);
      } else {
        await _player.resume();
      }
    }
    notifyListeners();
  }

  Future<void> next() async {
    if (queue.isEmpty) return;
    await _syncProgress();
    await _playAt(_nextIndex(index));
  }

  Future<void> prev() async {
    if (queue.isEmpty) return;
    // 播放超过 3 秒时回到开头，否则上一首
    if (_position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    await _syncProgress();
    await _playAt(_prevIndex(index));
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> setVolume(double v) => _player.setVolume(v.clamp(0.0, 1.0));

  /// 倍速 0.5x ~ 3.0x，持久化。
  Future<void> setSpeed(double s) async {
    s = s.clamp(0.5, 3.0);
    _speed = s;
    await _player.setPlaybackRate(s);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('play_speed', s);
    } catch (_) {}
    notifyListeners();
  }

  void cycleMode() {
    mode = switch (mode) {
      PlayMode.sequence => PlayMode.loop,
      PlayMode.loop => PlayMode.single,
      PlayMode.single => PlayMode.shuffle,
      PlayMode.shuffle => PlayMode.sequence,
    };
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
