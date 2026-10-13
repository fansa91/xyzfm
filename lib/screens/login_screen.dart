import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/api.dart';
import '../services/auth_service.dart';

/// 登录页：手机号短信验证码 / 扫码登录（均直连小宇宙官方接口）。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  bool _sending = false;
  bool _loggingIn = false;
  int _countdown = 0;
  Timer? _timer;

  /// 登录方式：sms 短信 / qrcode 扫码
  String _mode = 'sms';

  /// 扫码登录状态
  String? _qrId;
  String? _qrUrl;
  String _qrStatus = ''; // WAITTING / SCANNED / USED / EXPIRED / ERROR
  String? _qrError;
  Timer? _qrTimer;
  bool _qrBusy = false;

  @override
  void dispose() {
    _timer?.cancel();
    _qrTimer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdown <= 1) {
        t.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _snack('请输入手机号');
      return;
    }
    if (!RegExp(r'^\d{11}$').hasMatch(phone)) {
      _snack('请输入正确的 11 位手机号');
      return;
    }
    setState(() => _sending = true);
    try {
      await context.read<AuthService>().sendCode(phone);
      if (!mounted) return;
      _snack('验证码已发送，请注意查收');
      _startCountdown();
    } on XyzException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('发送失败：$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _login() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    if (phone.isEmpty || code.isEmpty) {
      _snack('请输入手机号和验证码');
      return;
    }
    setState(() => _loggingIn = true);
    try {
      await context.read<AuthService>().login(phone, code);
      if (!mounted) return;
      _snack('登录成功');
      Navigator.of(context).pop();
    } on XyzException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('登录失败：$e');
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  // ---------------- 扫码登录 ----------------

  void _switchMode(String mode) {
    if (_mode == mode) return;
    _qrTimer?.cancel();
    setState(() {
      _mode = mode;
      _qrId = null;
      _qrUrl = null;
      _qrStatus = '';
      _qrError = null;
    });
    if (mode == 'qrcode') _createQrcode();
  }

  Future<void> _createQrcode() async {
    _qrTimer?.cancel();
    setState(() {
      _qrBusy = true;
      _qrError = null;
      _qrId = null;
      _qrUrl = null;
      _qrStatus = '';
    });
    try {
      final session = await context.read<AuthService>().createQrcode();
      if (!mounted) return;
      setState(() {
        _qrId = session.id;
        _qrUrl = session.url;
        _qrStatus = 'WAITTING';
        _qrBusy = false;
      });
      _startQrPoll();
    } on XyzException catch (e) {
      if (!mounted) return;
      setState(() {
        _qrBusy = false;
        _qrError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _qrBusy = false;
        _qrError = '获取二维码失败：$e';
      });
    }
  }

  void _startQrPoll() {
    _qrTimer?.cancel();
    _qrTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      final id = _qrId;
      if (!mounted || id == null || _mode != 'qrcode') {
        t.cancel();
        return;
      }
      final auth = context.read<AuthService>();
      final result = await auth.pollQrcode(id);
      if (!mounted || _qrId != id) return;
      if (result.succeeded) {
        t.cancel();
        setState(() => _qrStatus = 'USED');
        try {
          await auth.finishQrcodeLogin(
              result.accessToken!, result.refreshToken);
          if (!mounted) return;
          _snack('登录成功');
          Navigator.of(context).pop();
        } on XyzException catch (e) {
          if (mounted) _snack(e.message);
        } catch (e) {
          if (mounted) _snack('登录失败：$e');
        }
        return;
      }
      if (result.expired) {
        t.cancel();
        if (mounted) setState(() => _qrStatus = 'EXPIRED');
        return;
      }
      // ERROR 时继续轮询；状态变化时刷新提示文案
      if (mounted && result.status != _qrStatus && result.status != 'ERROR') {
        setState(() => _qrStatus = result.status);
      }
    });
  }

  String _qrHint() {
    switch (_qrStatus) {
      case 'WAITTING':
        return '请用小宇宙 App 扫码';
      case 'SCANNED':
        return '已扫码，请在手机上确认登录';
      case 'USED':
        return '登录成功，正在进入…';
      case 'EXPIRED':
        return '二维码已失效，请重新获取';
      default:
        return '正在获取二维码…';
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          children: [
            const SizedBox(height: 40),
            Center(
              child: Icon(
                Icons.podcasts,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                '登录 xyzFM',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '登录后可同步订阅、收藏与收听进度',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // 登录方式切换
            Center(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'sms',
                    label: Text('短信登录'),
                    icon: Icon(Icons.sms_outlined),
                  ),
                  ButtonSegment(
                    value: 'qrcode',
                    label: Text('扫码登录'),
                    icon: Icon(Icons.qr_code_2_outlined),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => _switchMode(s.first),
              ),
            ),
            const SizedBox(height: 24),
            if (_mode == 'sms') ..._buildSms(theme) else ..._buildQrcode(theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSms(ThemeData theme) {
    return [
      // 手机号
      TextField(
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        maxLength: 11,
        decoration: const InputDecoration(
          labelText: '手机号',
          prefixText: '+86 ',
          border: OutlineInputBorder(),
          counterText: '',
        ),
      ),
      const SizedBox(height: 16),
      // 验证码
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: '验证码',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              onSubmitted: (_) => _login(),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonal(
            onPressed: (_sending || _countdown > 0) ? null : _sendCode,
            child: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_countdown > 0 ? '${_countdown}s' : '发送验证码'),
          ),
        ],
      ),
      const SizedBox(height: 28),
      FilledButton(
        onPressed: _loggingIn ? null : _login,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
        ),
        child: _loggingIn
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('登录', style: TextStyle(fontSize: 16)),
      ),
      const SizedBox(height: 16),
      Text(
        '未注册手机号将自动注册。登录即代表同意小宇宙的服务条款。',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  List<Widget> _buildQrcode(ThemeData theme) {
    return [
      Center(
        child: Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor),
          ),
          child: _qrBusy
              ? const Center(child: CircularProgressIndicator())
              : _qrError != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _qrError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            onPressed: _createQrcode,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    )
                  : _qrUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              QrImageView(
                                data: _qrUrl!,
                                size: 220,
                                backgroundColor: Colors.white,
                              ),
                              if (_qrStatus == 'EXPIRED')
                                Container(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text('二维码已失效'),
                                      const SizedBox(height: 8),
                                      FilledButton.tonal(
                                        onPressed: _createQrcode,
                                        child: const Text('重新获取'),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
        ),
      ),
      const SizedBox(height: 16),
      Center(
        child: Text(
          _qrHint(),
          style: TextStyle(
            fontSize: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      const SizedBox(height: 8),
      if (_qrStatus == 'WAITTING' || _qrStatus == 'SCANNED')
        Center(
          child: TextButton(
            onPressed: _createQrcode,
            child: const Text('刷新二维码'),
          ),
        ),
    ];
  }
}
