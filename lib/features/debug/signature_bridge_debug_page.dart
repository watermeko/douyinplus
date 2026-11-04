import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/widgets/glass.dart';
import '../../data/app_controller.dart';
import '../../data/signature_bridge.dart';

/// Debug-only spike page for the hidden-WebView signature bridge.
///
/// It is intentionally not part of the release flow. Use it to verify that
/// `comment/list` and `aweme/detail` can be executed from the official page
/// context with the logged-in WebView cookies.
class SignatureBridgeDebugPage extends StatefulWidget {
  const SignatureBridgeDebugPage({super.key, this.initialAwemeId});

  final String? initialAwemeId;

  @override
  State<SignatureBridgeDebugPage> createState() =>
      _SignatureBridgeDebugPageState();
}

class _SignatureBridgeDebugPageState extends State<SignatureBridgeDebugPage> {
  late final SignatureBridge _bridge;
  late final TextEditingController _awemeController;
  final List<String> _logs = <String>[];
  bool _busy = false;
  bool _showWebView = false;

  @override
  void initState() {
    super.initState();
    _bridge = SignatureBridge(
      sessionStore: context.read<AppController>().sessionStore,
    );
    _awemeController = TextEditingController(text: widget.initialAwemeId ?? '');
  }

  @override
  void dispose() {
    _awemeController.dispose();
    _bridge.dispose();
    super.dispose();
  }

  Future<void> _testComments() async {
    final awemeId = _awemeController.text.trim();
    if (awemeId.isEmpty) {
      _add('请先填写 aweme_id');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    final started = DateTime.now();
    var cursor = '0';
    var pages = 0;
    var loadedTotal = 0;
    var hasMore = true;
    Object? total;
    String? firstText;
    String? replyCid;
    int replyCount = 0;
    String? replyText;
    final lines = <String>[];

    while (hasMore && pages < 3) {
      final pageStarted = DateTime.now();
      final response = await _bridge.get('/aweme/v1/web/comment/list/', {
        'aweme_id': awemeId,
        'cursor': cursor,
        'count': '10',
        'item_type': '0',
      });
      final elapsed = DateTime.now().difference(pageStarted).inMilliseconds;
      if (!response.isSuccess) {
        _add(
          '评论分页 ❌ 第 ${pages + 1} 页 · '
          '${response.failureReason ?? '未知错误'} · '
          'HTTP ${response.statusCode} · '
          '${response.body.length} bytes · ${elapsed}ms',
        );
        if (mounted) setState(() => _busy = false);
        return;
      }
      final json = _tryJson(response.body);
      if (json == null) {
        _add('评论分页 ❌ 第 ${pages + 1} 页响应无法解析');
        if (mounted) setState(() => _busy = false);
        return;
      }
      final comments = json['comments'];
      final loaded = comments is List ? comments.length : 0;
      loadedTotal += loaded;
      pages++;
      total ??= json['total'];
      if (firstText == null && comments is List && comments.isNotEmpty) {
        final first = comments.first;
        if (first is Map) {
          firstText = first['text']?.toString();
        }
      }
      if (replyCid == null && comments is List) {
        final candidates = <Map>[];
        for (final comment in comments) {
          if (comment is Map &&
              ((comment['reply_comment_total'] as num?)?.toInt() ?? 0) > 0) {
            candidates.add(comment);
          }
        }
        if (candidates.isNotEmpty) {
          // Prefer a non-pinned reply thread when there is more than one.
          final target = candidates.length > 1
              ? candidates[1]
              : candidates.first;
          replyCid = target['cid']?.toString();
          replyCount = (target['reply_comment_total'] as num?)?.toInt() ?? 0;
          replyText = target['text']?.toString();
        }
      }
      cursor = json['cursor']?.toString() ?? '';
      hasMore = json['has_more'] == 1 || json['has_more'] == true;
      lines.add(
        '第 $pages 页 · HTTP ${response.statusCode} · '
        '${response.body.length}B · ${elapsed}ms · '
        'loaded=$loaded has_more=${json['has_more']}',
      );
      if (loaded == 0 || cursor.isEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    final elapsed = DateTime.now().difference(started).inMilliseconds;
    _add(
      '评论分页 ✅ $pages 页 · $loadedTotal 条 · total=$total · ${elapsed}ms\n'
      '${lines.join('\n')}\n'
      'first=${_truncate(firstText ?? '', 80)}',
    );

    if (replyCid != null && replyCount > 0) {
      _add(
        '回复候选 · replies=$replyCount · '
        'cid=…${replyCid.substring(replyCid.length - 6)} · '
        '${_truncate(replyText ?? '', 60)}',
      );
      final replyStarted = DateTime.now();
      final reply = await _bridge.getWithFetch(
        '/aweme/v1/web/comment/list/reply/',
        <String, String>{
          'item_id': awemeId,
          'aweme_id': awemeId,
          'comment_id': replyCid,
          'cursor': '0',
          'count': '20',
          'item_type': '0',
          'app_name': 'aweme',
          'app_type': 'web',
        },
      );
      final replyElapsed = DateTime.now()
          .difference(replyStarted)
          .inMilliseconds;
      if (!reply.isSuccess) {
        _add(
          '回复 ❌ ${reply.failureReason ?? '未知错误'} · '
          'HTTP ${reply.statusCode} · ${reply.body.length} bytes · '
          '${replyElapsed}ms',
        );
      } else {
        final json = _tryJson(reply.body);
        final replies = json?['comments'];
        final firstReply = replies is List && replies.isNotEmpty
            ? (replies.first as Map)['text']
            : null;
        _add(
          '回复 ✅ HTTP ${reply.statusCode} · ${reply.body.length} bytes · '
          '${replyElapsed}ms · loaded=${replies is List ? replies.length : 0} '
          'has_more=${json?['has_more']}\n'
          'first=${_truncate(firstReply?.toString() ?? '', 80)}',
        );
      }
    } else {
      _add('首条评论无可展开回复，跳过 reply 接口');
    }

    if (mounted) setState(() => _busy = false);
  }

  Future<void> _testDetail() async {
    final awemeId = _awemeController.text.trim();
    if (awemeId.isEmpty) {
      _add('请先填写 aweme_id');
      return;
    }
    await _run(
      '详情',
      () {
        return _bridge.get('/aweme/v1/web/aweme/detail/', <String, String>{
          'aweme_id': awemeId,
        });
      },
      (response, json, elapsed) {
        final detail = json?['aweme_detail'];
        final video = detail is Map ? detail['video'] : null;
        final playAddr = video is Map ? video['play_addr'] : null;
        final urls = playAddr is Map ? playAddr['url_list'] : null;
        return '详情 ✅ HTTP ${response.statusCode} · '
            '${response.body.length} bytes · ${elapsed}ms\n'
            'status_code=${json?['status_code']} '
            'aweme_id=${detail is Map ? detail['aweme_id'] : '—'} '
            'desc=${_truncate(detail is Map ? (detail['desc']?.toString() ?? '') : '', 80)}\n'
            'size=${video is Map ? '${video['width']}x${video['height']}' : '—'} '
            'play_urls=${urls is List ? urls.length : 0}';
      },
    );
  }

  Future<void> _run(
    String label,
    Future<SignatureResponse> Function() request,
    String Function(
      SignatureResponse response,
      Map<String, dynamic>? json,
      int elapsedMs,
    )
    describe,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    final started = DateTime.now();
    final response = await request();
    final elapsed = DateTime.now().difference(started).inMilliseconds;
    if (!mounted) return;
    final json = _tryJson(response.body);
    if (response.isSuccess) {
      _add(describe(response, json, elapsed));
    } else {
      final reason = response.failureReason ?? '未知错误';
      final snippet = _truncate(
        response.body.replaceAll(RegExp(r'\s+'), ' '),
        180,
      );
      _add(
        '$label ❌ $reason · HTTP ${response.statusCode} · '
        '${response.body.length} bytes · ${elapsed}ms\n$snippet',
      );
    }
    if (mounted) setState(() => _busy = false);
  }

  Map<String, dynamic>? _tryJson(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _truncate(String value, int max) {
    final clean = value.replaceAll('\n', ' ').trim();
    if (clean.length <= max) return clean;
    return '${clean.substring(0, max)}…';
  }

  void _add(String message) {
    if (!mounted) return;
    setState(() {
      _logs.insert(0, message);
      if (_logs.length > 20) _logs.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 160),
              children: [
                Row(
                  children: [
                    GlassIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      size: 40,
                      iconSize: 17,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      '签名桥测试',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    _StatusChip(bridge: _bridge),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '仅 Debug 构建可见。请求在官方页面上下文执行，Cookie 不会离开本机。',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.48),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _awemeController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'aweme_id',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.32),
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.cyan),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GlassButton(
                        label: '读取评论',
                        icon: Icons.forum_outlined,
                        onTap: _busy ? null : _testComments,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GlassButton(
                        label: '读取详情',
                        icon: Icons.movie_outlined,
                        onTap: _busy ? null : _testDetail,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GlassButton(
                        label: '重载签名页',
                        icon: Icons.refresh_rounded,
                        onTap: _busy
                            ? null
                            : () {
                                _add('重新加载 WebView 页面…');
                                _bridge.reloadPage();
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '显示 WebView（排查登录/验证码）',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                    Switch(
                      value: _showWebView,
                      activeThumbColor: AppColors.pink,
                      onChanged: (value) =>
                          setState(() => _showWebView = value),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '请求结果',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: Colors.white.withValues(alpha: 0.42),
                  ),
                ),
                const SizedBox(height: 8),
                if (_logs.isEmpty)
                  Text(
                    '还没有发起请求。先点“读取评论”或“读取详情”。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.36),
                    ),
                  )
                else
                  for (final log in _logs) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: SelectableText(
                        log,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.45,
                          fontFamily: 'monospace',
                          color: Colors.white.withValues(alpha: 0.78),
                        ),
                      ),
                    ),
                  ],
              ],
            ),
            Positioned(
              left: _showWebView ? 14 : 0,
              bottom: _showWebView ? 14 : 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_showWebView)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 6),
                      child: Text(
                        '签名 WebView 预览',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  Container(
                    decoration: _showWebView
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.24),
                            ),
                          )
                        : null,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        _showWebView ? 14 : 0,
                      ),
                      child: SignatureBridgeHost(
                        bridge: _bridge,
                        expanded: _showWebView,
                        expandedSize: const Size(300, 420),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.bridge});

  final SignatureBridge bridge;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SignatureBridgeStatus>(
      valueListenable: bridge.status,
      builder: (context, status, _) {
        final (label, color) = switch (status) {
          SignatureBridgeStatus.idle => ('未启动', Colors.white38),
          SignatureBridgeStatus.loading => ('加载中', AppColors.amber),
          SignatureBridgeStatus.ready => ('就绪', AppColors.cyan),
          SignatureBridgeStatus.error => ('异常', AppColors.rose),
        };
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
