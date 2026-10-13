import 'package:flutter_test/flutter_test.dart';
import 'package:netease_music/core/api.dart';
import 'package:netease_music/services/music_service.dart';

/// 联网集成测试：用真实新接口验证播放取链行为。
/// 解释"暂无版权"：未登录时需要登录的歌曲返回 null。
void main() {
  test('免费歌曲未登录也能取到播放链接', () async {
    final music = MusicService(ApiClient());
    final url = await music.songUrl(3433437362); // 两难pt.2
    expect(url, isNotNull);
    expect(url!, startsWith('http'));
  });

  test('周杰伦《晴天》未登录时返回 null（暂无版权）', () async {
    final music = MusicService(ApiClient());
    final url = await music.songUrl(186016, level: 'standard');
    // 网易云要求登录/VIP，该接口返回空 -> App 显示"暂无版权，已跳过"
    expect(url, isNull);
  });

  test('搜索接口正常', () async {
    final api = ApiClient();
    final d = await api.get('/search', {'keywords': '晴天', 'limit': 1});
    final songs = d['result']?['songs'] as List?;
    expect(songs, isNotNull);
    expect(songs!.isNotEmpty, true);
  });
}
