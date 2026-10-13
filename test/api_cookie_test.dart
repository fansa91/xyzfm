import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netease_music/core/api.dart';

/// 验证 ApiClient 的核心行为：默认接口、URL 规范化、cookie 携带。
void main() {
  test('默认接口地址是新 API', () {
    expect(ApiClient.defaultBaseUrl, 'https://sg.fansa.nyc.mn/netease');
  });

  test('setBaseUrl 自动去掉末尾斜杠', () {
    final api = ApiClient();
    api.setBaseUrl('https://sg.fansa.nyc.mn/netease///');
    expect(api.dio.options.baseUrl, 'https://sg.fansa.nyc.mn/netease');
  });

  test('登录后请求自动带上 cookie 参数', () async {
    final api = ApiClient();
    api.cookie = 'MUSIC_U=test123; __csrf=abc';
    Uri? captured;
    api.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        captured = options.uri;
        handler.resolve(
            Response(requestOptions: options, data: {'code': 200}));
      },
    ));

    await api.get('/song/url/v1', {'id': 186016, 'level': 'standard'});

    expect(captured, isNotNull);
    // cookie 必须作为 query 参数发出
    expect(
        captured!.queryParameters['cookie'], 'MUSIC_U=test123; __csrf=abc');
    expect(captured!.queryParameters['id'], '186016');
    expect(captured!.queryParameters.containsKey('timestamp'), true);
  });

  test('未登录时不带 cookie 参数', () async {
    final api = ApiClient();
    Uri? captured;
    api.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        captured = options.uri;
        handler.resolve(
            Response(requestOptions: options, data: {'code': 200}));
      },
    ));

    await api.get('/banner', {'type': 1});

    expect(captured, isNotNull);
    expect(captured!.queryParameters.containsKey('cookie'), false);
  });
}
