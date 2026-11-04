import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/liquid_background.dart';
import '../../data/app_controller.dart';

class DevCookieImportPage extends StatefulWidget {
  const DevCookieImportPage({super.key});

  @override
  State<DevCookieImportPage> createState() => _DevCookieImportPageState();
}

class _DevCookieImportPageState extends State<DevCookieImportPage> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  bool _isError = false;
  String? _message;
  String? _debugFilePath;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      _resolveDebugPath();
    }
  }

  Future<void> _resolveDebugPath() async {
    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null || !mounted) return;
      setState(() {
        _debugFilePath = '${directory.path}/douyin_cookies.json';
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _importText() async {
    final app = context.read<AppController>();
    final cookies = AppController.parseCookieInput(_controller.text);
    if (cookies.isEmpty) {
      setState(() {
        _isError = true;
        _message = '无法解析 Cookie。请粘贴 JSON 对象或 a=b; c=d 格式。';
      });
      return;
    }
    await _runImport(() => app.importCookies(cookies));
  }

  Future<void> _importFile() async {
    final app = context.read<AppController>();
    await _runImport(() => app.importDebugCookieFile());
  }

  Future<void> _runImport(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _isError = false;
    });
    final app = context.read<AppController>();
    final ok = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _isError = !ok;
      _message = ok
          ? '导入成功，正在进入推荐流…'
          : (app.error ?? '导入失败，请检查 sessionid 是否有效');
    });
    if (ok) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final topPadding = MediaQuery.paddingOf(context).top;

    return Scaffold(
      body: LiquidBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18, topPadding > 0 ? 8 : 18, 18, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GlassIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      size: 42,
                      iconSize: 18,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      '开发调试 · Cookie 导入',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                GlassSurface(
                  radius: 28,
                  blur: 24,
                  opacity: 0.16,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.amber,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '仅 Debug 构建可见',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.62),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '从已登录的浏览器导出抖音 Cookie，粘贴到下方。'
                        '至少需要 sessionid 与 ttwid。',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.55,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _controller,
                        minLines: 6,
                        maxLines: 10,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          fontFamily: 'monospace',
                          color: Colors.white,
                        ),
                        decoration: InputDecoration(
                          hintText: '{"sessionid": "...", "ttwid": "...", "UIFID": "..."}',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.26),
                          ),
                          filled: true,
                          fillColor: Colors.black.withValues(alpha: 0.24),
                          contentPadding: const EdgeInsets.all(14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: AppColors.pink.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      GlassButton(
                        label: _busy ? '正在校验…' : '导入并校验',
                        icon: Icons.login_rounded,
                        primary: true,
                        loading: _busy,
                        onTap: _busy ? null : _importText,
                      ),
                      const SizedBox(height: 10),
                      GlassButton(
                        label: '从调试文件导入',
                        icon: Icons.folder_open_rounded,
                        onTap: _busy ? null : _importFile,
                      ),
                      if (_debugFilePath != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          '调试文件路径：\n$_debugFilePath',
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.5,
                            fontFamily: 'monospace',
                            color: Colors.white.withValues(alpha: 0.36),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'adb push cookies.json $_debugFilePath',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                        ),
                      ],
                      if (_message != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: (_isError ? AppColors.pink : AppColors.cyan)
                                .withValues(alpha: 0.12),
                            border: Border.all(
                              color:
                                  (_isError ? AppColors.pink : AppColors.cyan)
                                      .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            _message!,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.45,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Text(
                        '当前会话：${app.profile?.nickname ?? "未登录"}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.34),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '提示：正式版本不会展示此页面。Cookie 等价于账号密码，请勿提交到 Git 或发送给他人。',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.6,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
