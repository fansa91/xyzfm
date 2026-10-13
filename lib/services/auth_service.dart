import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../models/models.dart';

/// 登录状态管理：短信验证码登录（直连小宇宙官方 podcaster-api），token 持久化。
///
/// 登录流程（照抄 ultrazg/xyz 项目 login.go 抓到的官方请求）：
/// - 发码：POST https://podcaster-api.xiaoyuzhoufm.com/v1/auth/send-code（浏览器 UA 头）
/// - 登录：POST https://podcaster-api.xiaoyuzhoufm.com/v1/auth/login-with-sms（浏览器 UA 头）
/// - **token 在响应头** `x-jike-access-token` / `x-jike-refresh-token` 里，
///   用户信息在 body 的 `data.user`（{uid, nickname, avatar{picture{...}}, bio}）。
///
/// 扫码登录（照抄 ultrazg/horizon 项目 bridge/http.go 抓到的官方 web-api）：
/// - 建码：POST https://web-api.xiaoyuzhoufm.com/v1/auth/qrcode/create
///   body {"clientId": "xyz-web"} → {"id", "url"}（url 即二维码内容）
/// - 轮询：POST https://web-api.xiaoyuzhoufm.com/v1/auth/qrcode/login
///   body {"id"} → 确认后 token 同样在响应头里，body.status 为 USED；
///   轮询返回 400/401 表示二维码已失效。
class AuthService extends ChangeNotifier {
  static const _sendCodeUrl =
      'https://podcaster-api.xiaoyuzhoufm.com/v1/auth/send-code';
  static const _loginUrl =
      'https://podcaster-api.xiaoyuzhoufm.com/v1/auth/login-with-sms';

  static const _keyAccessToken = 'xyz_access_token';
  static const _keyRefreshToken = 'xyz_refresh_token';
  static const _keyUid = 'xyz_uid';
  static const _keyNickname = 'xyz_nickname';
  static const _keyDeviceId = 'xyz_device_id';
  static const _keyAvatar = 'xyz_avatar';
  static const _keyBio = 'xyz_bio';

  final XyzApiClient api;

  SharedPreferences? _prefs;
  bool _loading = true;
  bool _loggedIn = false;
  String _uid = '';
  String _nickname = '';
  String _avatar = '';
  String _bio = '';

  bool get loading => _loading;
  bool get loggedIn => _loggedIn;
  String get uid => _uid;
  String get nickname => _nickname;
  String get bio => _bio;

  /// 头像直链：登录时已用 picUrl 解包 avatar 对象得到。
  String get avatarUrl => _avatar;

  AuthService(this.api) {
    // token 被 api 内部刷新后，把新 token 持久化
    api.onTokensChanged = (access, refresh) async {
      final p = _prefs;
      if (p == null) return;
      await p.setString(_keyAccessToken, access ?? '');
      await p.setString(_keyRefreshToken, refresh ?? '');
    };
  }

  /// 发送短信验证码。
  Future<void> sendCode(String phone, {String areaCode = '+86'}) async {
    await api.postAuth(_sendCodeUrl, {
      'mobilePhoneNumber': phone.trim(),
      'areaCode': areaCode,
    });
  }

  /// 短信验证码登录。成功后持久化 token 与用户信息。
  Future<void> login(String phone, String code,
      {String areaCode = '+86'}) async {
    final resp = await api.postAuth(_loginUrl, {
      'areaCode': areaCode,
      'verifyCode': code.trim(),
      'mobilePhoneNumber': phone.trim(),
    });
    final access = resp.headers.value('x-jike-access-token');
    final refresh = resp.headers.value('x-jike-refresh-token');
    if (access == null || access.isEmpty) {
      throw XyzException('登录失败：未返回 token');
    }
    final body = resp.data is Map
        ? Map<String, dynamic>.from(resp.data as Map)
        : <String, dynamic>{};
    final data = body['data'] is Map
        ? Map<String, dynamic>.from(body['data'] as Map)
        : <String, dynamic>{};
    final user = data['user'] is Map
        ? Map<String, dynamic>.from(data['user'] as Map)
        : <String, dynamic>{};
    _uid = str(user['uid']);
    _nickname = str(user['nickname']);
    _avatar = picUrl(user['avatar']);
    _bio = str(user['bio']);

    api.setTokens(access, refresh);
    _loggedIn = true;
    _loading = false;
    await _persist();
    notifyListeners();
  }

  /// 创建扫码登录会话，返回 (id, url)，url 即二维码内容。
  Future<({String id, String url})> createQrcode() async {
    final resp = await api.postQrcode(
      '/v1/auth/qrcode/create',
      {'clientId': 'xyz-web'},
    );
    final data = resp.data is Map
        ? Map<String, dynamic>.from(resp.data as Map)
        : <String, dynamic>{};
    final id = str(data['id']);
    final url = str(data['url']);
    if (id.isEmpty || url.isEmpty) throw XyzException('获取二维码失败');
    return (id: id, url: url);
  }

  /// 轮询扫码状态：WAITTING（等扫码）/ SCANNED（已扫待确认）/
  /// USED（已确认，带 token）/ EXPIRED（已失效）/ ERROR（网络等错误）。
  Future<QrcodePollResult> pollQrcode(String id) async {
    try {
      final resp = await api.postQrcode('/v1/auth/qrcode/login', {'id': id});
      final access = resp.headers.value('x-jike-access-token');
      final refresh = resp.headers.value('x-jike-refresh-token');
      if (access != null && access.isNotEmpty) {
        return QrcodePollResult.used(access, refresh);
      }
      final data = resp.data is Map
          ? Map<String, dynamic>.from(resp.data as Map)
          : <String, dynamic>{};
      final status = str(data['status']);
      return QrcodePollResult(status.isEmpty ? 'WAITTING' : status);
    } on XyzException catch (e) {
      if (e.statusCode == 400 || e.statusCode == 401) {
        return const QrcodePollResult('EXPIRED');
      }
      return const QrcodePollResult('ERROR');
    }
  }

  /// 扫码确认后：写入 token，拉取用户信息，完成登录。
  Future<void> finishQrcodeLogin(String accessToken, String? refreshToken) async {
    api.setTokens(accessToken, refreshToken);
    final resp = await api.get('/v1/profile/get');
    final data = resp['data'] is Map
        ? Map<String, dynamic>.from(resp['data'] as Map)
        : <String, dynamic>{};
    final nickname = str(data['nickname']);
    if (nickname.isEmpty) throw XyzException('登录失败：获取用户信息失败');
    _uid = str(data['uid']);
    _nickname = nickname;
    _avatar = picUrl(data['avatar']);
    _bio = str(data['bio']);
    _loggedIn = true;
    _loading = false;
    await _persist();
    notifyListeners();
  }

  /// 启动时恢复登录态：读 prefs 恢复 token；若有 token 则用
  /// GET `/v1/profile/get?uid=` 校验有效性（token 过期会自动尝试刷新），
  /// 失败则登出。
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // 设备 ID：评论等接口必需，首次生成后持久化（UUID v4 大写格式）。
    var deviceId = _prefs!.getString(_keyDeviceId) ?? '';
    if (deviceId.isEmpty) {
      deviceId = _generateDeviceId();
      await _prefs!.setString(_keyDeviceId, deviceId);
    }
    api.deviceId = deviceId;
    final access = _prefs!.getString(_keyAccessToken);
    final refresh = _prefs!.getString(_keyRefreshToken);
    if (access != null && access.isNotEmpty) {
      api.setTokens(access, refresh);
      _uid = _prefs!.getString(_keyUid) ?? '';
      _nickname = _prefs!.getString(_keyNickname) ?? '';
      _avatar = _prefs!.getString(_keyAvatar) ?? '';
      _bio = _prefs!.getString(_keyBio) ?? '';
      _loggedIn = true;
      try {
        final resp = await api.get('/v1/profile/get?uid=$_uid');
        final data = resp['data'] is Map
            ? Map<String, dynamic>.from(resp['data'] as Map)
            : <String, dynamic>{};
        final nickname = str(data['nickname']);
        if (nickname.isEmpty) throw XyzException('登录已失效');
        _nickname = nickname;
        final avatar = picUrl(data['avatar']);
        if (avatar.isNotEmpty) _avatar = avatar;
        final bio = str(data['bio']);
        if (bio.isNotEmpty) _bio = bio;
        await _persist();
      } catch (_) {
        await logout();
      }
    }
    _loading = false;
    notifyListeners();
  }

  /// 登出：清空 token、用户信息与持久化数据。
  Future<void> logout() async {
    api.setTokens(null, null);
    _loggedIn = false;
    _uid = '';
    _nickname = '';
    _avatar = '';
    _bio = '';
    final p = _prefs;
    if (p != null) {
      await p.remove(_keyAccessToken);
      await p.remove(_keyRefreshToken);
      await p.remove(_keyUid);
      await p.remove(_keyNickname);
      await p.remove(_keyAvatar);
      await p.remove(_keyBio);
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final p = _prefs;
    if (p == null) return;
    await p.setString(_keyAccessToken, api.accessToken ?? '');
    await p.setString(_keyRefreshToken, api.refreshToken ?? '');
    await p.setString(_keyUid, _uid);
    await p.setString(_keyNickname, _nickname);
    await p.setString(_keyAvatar, _avatar);
    await p.setString(_keyBio, _bio);
  }

  /// 生成 UUID v4（大写连字符格式），对齐官方 App 的 x-jike-device-id。
  static String _generateDeviceId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h =
        b.map((e) => e.toRadixString(16).padLeft(2, '0').toUpperCase()).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}

/// 扫码登录轮询结果。
class QrcodePollResult {
  /// WAITTING（等扫码）/ SCANNED（已扫待确认）/ USED（已确认，带 token）/
  /// EXPIRED（已失效）/ ERROR（网络等错误，可继续轮询）。
  final String status;
  final String? accessToken;
  final String? refreshToken;

  const QrcodePollResult(this.status, {this.accessToken, this.refreshToken});

  const QrcodePollResult.used(String access, String? refresh)
      : this('USED', accessToken: access, refreshToken: refresh);

  bool get succeeded => status == 'USED' && (accessToken ?? '').isNotEmpty;
  bool get expired => status == 'EXPIRED';
}
