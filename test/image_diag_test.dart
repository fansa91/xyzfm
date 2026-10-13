import 'package:flutter_test/flutter_test.dart';
import 'package:netease_music/core/api.dart';
import 'package:netease_music/services/music_service.dart';

/// 诊断图片缺失：打印各接口解析出的图片 URL。
void main() {
  late MusicService music;
  setUpAll(() => music = MusicService(ApiClient()));

  test('搜索歌曲封面', () async {
    final r = await music.search('晴天', 1, limit: 3);
    for (final s in r.songs) {
      // ignore: avoid_print
      print('SONG ${s.name} -> ${s.picUrl.isEmpty ? "EMPTY!" : s.picUrl}');
    }
  });

  test('搜索专辑封面', () async {
    final r = await music.search('晴天', 10, limit: 3);
    for (final a in r.albums) {
      // ignore: avoid_print
      print('ALBUM ${a.name} -> ${a.picUrl.isEmpty ? "EMPTY!" : a.picUrl}');
    }
  });

  test('搜索歌手图片', () async {
    final r = await music.search('周杰伦', 100, limit: 3);
    for (final a in r.artists) {
      // ignore: avoid_print
      print('ARTIST ${a.name} -> ${a.picUrl.isEmpty ? "EMPTY!" : a.picUrl}');
    }
  });

  test('热门歌手图片', () async {
    final list = await music.hotArtists(limit: 5);
    for (final a in list) {
      // ignore: avoid_print
      print('HOT ${a.name} -> ${a.picUrl.isEmpty ? "EMPTY!" : a.picUrl}');
    }
  });
}
