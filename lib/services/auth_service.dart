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
class AuthService extends ChangeNotifier {
  static const _sendCodeUrl =
      'https://podcaster-api.xiaoyuzhoufm.com/v1/auth/send-code';
  static const _loginUrl =
      'https://podcaster-api.xiaoyuzhoufm.com/v1/auth/login-with-sms';

  static const _keyAccessToken = 'xyz_access_token';
  static const _keyRefreshToken = 'xyz_refresh_token';
  static const _keyUid = 'xyz_uid';
  static const _keyNickname = 'xyz_nickname';
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

  /// 启动时恢复登录态：读 prefs 恢复 token；若有 token 则用
  /// GET `/v1/profile/get?uid=` 校验有效性（token 过期会自动尝试刷新），
  /// 失败则登出。
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
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
}
