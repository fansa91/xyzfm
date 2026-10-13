import 'package:dio/dio.dart';

import 'utils.dart';

/// 请求失败时抛出的异常（HTTP 非 2xx 或上游返回 error 字段）。
class XyzException implements Exception {
  final String message;

  /// HTTP 状态码（有的话），比如扫码轮询时 400/401 表示二维码已失效。
  final int? statusCode;

  XyzException(this.message, {this.statusCode});

  @override
  String toString() => 'XyzException: $message';
}

/// 直连小宇宙官方 API（https://api.xiaoyuzhoufm.com）的统一 HTTP 客户端。
/// 请求头照抄 ultrazg/xyz 项目 handlers 里抓到的官方 App 请求头
/// （Xiaoyuzhou/2.57.1 iOS 17.4.1）。
///
/// 约定：
/// - 内容接口：`post(path, body)` / `get(path)`，path 如 `/v1/discovery-feed/list`，
///   自动拼接 baseUrl 并带 App 请求头（含动态 Local-Time）；
/// - 上游响应是**直接 JSON**（通常 `{data: <载荷>, ...}`），**没有**信封层，
///   post/get 返回整个上游 JSON Map，由 XyzService 取 `resp['data']`；
/// - 登录/发码：`postAuth(url, body)` 走浏览器 UA 头，返回原始 Dio Response
///   （token 在**响应头** `x-jike-access-token` / `x-jike-refresh-token` 里）；
/// - 401（HTTP 状态或上游 error.code）时自动调 `/app_auth_tokens.refresh`
///   刷新 token（新 token 同样从响应头取）并重试一次；刷新失败则抛 XyzException。
class XyzApiClient {
  /// 内容接口 BaseUrl，固定不再可配置。
  static const String baseUrl = 'https://api.xiaoyuzhoufm.com';

  static const String _abtestDefault = '{"old_user_discovery_feed":"enable"}';

  final Dio _dio;
  String? _accessToken;
  String? _refreshToken;

  /// token 被设置/刷新/清空时的回调，供 AuthService 做持久化。
  void Function(String? access, String? refresh)? onTokensChanged;

  XyzApiClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          responseType: ResponseType.json,
        ));

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get hasToken => _accessToken != null && _accessToken!.isNotEmpty;

  void setTokens(String? access, String? refresh) {
    _accessToken = (access == null || access.isEmpty) ? null : access;
    _refreshToken = (refresh == null || refresh.isEmpty) ? null : refresh;
    onTokensChanged?.call(_accessToken, _refreshToken);
  }

  /// 官方 App 请求头。abtestInfo 个别接口为 "{}"（如 favorite/list），默认 enable。
  Map<String, String> _appHeaders({
    String? abtestInfo,
    String? contentType,
  }) {
    return {
      'Host': 'api.xiaoyuzhoufm.com',
      'User-Agent': 'Xiaoyuzhou/2.57.1 (build:1576; iOS 17.4.1)',
      'Market': 'AppStore',
      'App-BuildNo': '1576',
      'OS': 'ios',
      if (_accessToken != null && _accessToken!.isNotEmpty)
        'x-jike-access-token': _accessToken!,
      'Manufacturer': 'Apple',
      'BundleID': 'app.podcast.cosmos',
      'abtest-info': abtestInfo ?? _abtestDefault,
      'Accept-Language': 'zh-Hant-HK;q=1.0, zh-Hans-CN;q=0.9',
      'Model': 'iPhone14,2',
      'app-permissions': '4',
      'Accept': '*/*',
      'Content-Type': contentType ?? 'application/json',
      'App-Version': '2.57.1',
      'WifiConnected': 'true',
      'OS-Version': '17.4.1',
      'x-custom-xiaoyuzhou-app-dev': '',
      'Local-Time': DateTime.now().toIso8601String(),
      'Timezone': 'Asia/Shanghai',
    };
  }

  /// POST 内容接口，返回整个上游 JSON Map。401 自动刷新重试一次。
  Future<Map<String, dynamic>> post(
    String path, [
    Map<String, dynamic>? body,
    String? abtestInfo,
  ]) {
    return _request(
      () => _dio.post(
        '$baseUrl$path',
        data: body ?? <String, dynamic>{},
        options: Options(headers: _appHeaders(abtestInfo: abtestInfo)),
      ),
    );
  }

  /// GET 内容接口（path 可带 query，如 `/v1/podcast/get?pid=xxx`）。
  Future<Map<String, dynamic>> get(String path, [String? abtestInfo]) {
    return _request(
      () => _dio.get(
        '$baseUrl$path',
        options: Options(headers: _appHeaders(abtestInfo: abtestInfo)),
      ),
    );
  }

  /// 登录/发码专用：向完整 URL 发 POST，带浏览器 UA 头。
  /// 返回原始 Response（token 在响应头里，用户信息在 body 的 data.user）。
  Future<Response> postAuth(String url, Map<String, dynamic> body) async {
    const headers = {
      'accept': 'application/json, text/plain, */*',
      'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
      'content-type': 'application/json;charset=UTF-8',
      'origin': 'https://podcaster.xiaoyuzhoufm.com',
      'referer': 'https://podcaster.xiaoyuzhoufm.com/',
      'user-agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36 Edg/146.0.0.0',
    };
    try {
      return await _dio.post(
        url,
        data: body,
        options: Options(headers: headers),
      );
    } on DioException catch (e) {
      throw XyzException(
        _errorMessage(e.response?.data) ?? '请求失败，请稍后重试',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// 扫码登录专用：走小宇宙 web-api（https://web-api.xiaoyuzhoufm.com），
  /// 请求头照抄 ultrazg/horizon 项目 bridge/http.go 里抓到的官方 web 请求。
  /// 返回原始 Response：成功时 token 在响应头
  /// `x-jike-access-token` / `x-jike-refresh-token` 里。
  Future<Response> postQrcode(String path, Map<String, dynamic> body) async {
    const headers = {
      'content-type': 'application/json;charset=UTF-8',
      'x-midway-app-id': 'v6worU4NnWyL',
      'origin': 'https://accounts.xiaoyuzhoufm.com/',
      'referer': 'https://accounts.xiaoyuzhoufm.com/',
      'user-agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36',
    };
    try {
      return await _dio.post(
        'https://web-api.xiaoyuzhoufm.com$path',
        data: body,
        options: Options(headers: headers),
      );
    } on DioException catch (e) {
      throw XyzException(
        _errorMessage(e.response?.data) ?? '请求失败，请稍后重试',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> _request(
    Future<Response> Function() send, {
    bool allowRefresh = true,
  }) async {
    Response resp;
    try {
      resp = await send();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 && allowRefresh && await _refreshTokens()) {
        return _request(send, allowRefresh: false);
      }
      throw XyzException(
        _errorMessage(e.response?.data) ??
            '网络请求失败${status != null ? '（HTTP $status）' : ''}',
      );
    }
    final data = _asMap(resp.data);
    final err = data['error'];
    if (err != null) {
      final msg = _errorMessage(data) ?? '请求失败';
      final code = err is Map ? intOf(err['code']) : 0;
      if (code == 401 && allowRefresh && await _refreshTokens()) {
        return _request(send, allowRefresh: false);
      }
      throw XyzException(msg);
    }
    return data;
  }

  /// 调上游 `/app_auth_tokens.refresh` 刷新 token，新 token 从响应头取。
  /// 成功返回 true；内部不触发二次刷新，避免递归。
  Future<bool> _refreshTokens() async {
    final access = _accessToken;
    final refresh = _refreshToken;
    if (access == null || access.isEmpty || refresh == null || refresh.isEmpty) {
      return false;
    }
    try {
      final headers = _appHeaders(
        contentType: 'application/x-www-form-urlencoded; charset=utf-8',
      );
      headers['x-jike-refresh-token'] = refresh;
      final resp = await _dio.post(
        '$baseUrl/app_auth_tokens.refresh',
        options: Options(headers: headers),
      );
      final newAccess = resp.headers.value('x-jike-access-token');
      if (newAccess != null && newAccess.isNotEmpty) {
        final newRefresh = resp.headers.value('x-jike-refresh-token');
        setTokens(
          newAccess,
          newRefresh != null && newRefresh.isNotEmpty ? newRefresh : refresh,
        );
        return true;
      }
    } catch (_) {
      // 刷新失败：交由上层按 401 处理
    }
    return false;
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  /// 从上游响应里提取错误信息。上游错误形如 `{"error": {"code": x, "message": "..."}}`。
  String? _errorMessage(dynamic data) {
    final m = _asMap(data);
    final err = m['error'];
    if (err == null) return null;
    if (err is String && err.isNotEmpty) return err;
    if (err is Map) {
      for (final k in ['message', 'msg', 'detail']) {
        final v = err[k];
        if (v is String && v.isNotEmpty) return v;
      }
      final code = err['code'];
      return code != null ? '请求失败（$code）' : '请求失败';
    }
    return '请求失败';
  }
}
