import 'dart:async';

import 'package:douyinplus/data/interaction_repository.dart';
import 'package:douyinplus/data/interactions_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGateway implements InteractionGateway {
  bool likeFails = false;
  bool collectFails = false;
  Completer<void>? likeGate;
  InteractionState? state;
  final List<String> likeCalls = <String>[];
  final List<String> collectCalls = <String>[];
  final List<String> stateCalls = <String>[];

  @override
  Future<InteractionState?> fetchState(String awemeId) async {
    stateCalls.add(awemeId);
    return state;
  }

  @override
  Future<void> setDigg({required String awemeId, required bool liked}) async {
    likeCalls.add('$awemeId:${liked ? 1 : 0}');
    if (likeGate != null) await likeGate!.future;
    if (likeFails) throw const InteractionException('点赞失败');
  }

  @override
  Future<void> setCollect({
    required String awemeId,
    required bool collected,
    int awemeType = 0,
  }) async {
    collectCalls.add('$awemeId:${collected ? 1 : 0}:$awemeType');
    if (collectFails) throw const InteractionException('收藏失败');
  }
}

void main() {
  test('like updates optimistically and keeps state on success', () async {
    final gateway = _FakeGateway();
    final controller = InteractionsController(gateway: gateway);

    final future = controller.toggleLike('a1');
    expect(controller.isLiked('a1'), isTrue);
    expect(controller.likeDelta('a1'), 1);
    expect(await future, isNull);
    expect(gateway.likeCalls, ['a1:1']);

    expect(await controller.toggleLike('a1'), isNull);
    expect(controller.isLiked('a1'), isFalse);
    expect(controller.likeDelta('a1'), 0);
    expect(gateway.likeCalls, ['a1:1', 'a1:0']);
    controller.dispose();
  });

  test('like rolls back and returns the error message on failure', () async {
    final gateway = _FakeGateway()..likeFails = true;
    final controller = InteractionsController(gateway: gateway);

    final error = await controller.toggleLike('a1');
    expect(error, '点赞失败');
    expect(controller.isLiked('a1'), isFalse);
    expect(controller.likeDelta('a1'), 0);
    controller.dispose();
  });

  test('collect passes aweme type and rolls back on failure', () async {
    final gateway = _FakeGateway();
    final controller = InteractionsController(gateway: gateway);

    expect(await controller.toggleCollect('a2', awemeType: 2), isNull);
    expect(controller.isCollected('a2'), isTrue);
    expect(controller.collectDelta('a2'), 1);
    expect(gateway.collectCalls, ['a2:1:2']);

    gateway.collectFails = true;
    final error = await controller.toggleCollect('a2', awemeType: 2);
    expect(error, '收藏失败');
    expect(controller.isCollected('a2'), isTrue);
    expect(controller.collectDelta('a2'), 1);
    controller.dispose();
  });

  test('hydrate applies the server like / collect state once', () async {
    final gateway = _FakeGateway()
      ..state = const InteractionState(liked: true, collected: true);
    final controller = InteractionsController(gateway: gateway);

    await controller.hydrate('a1');
    expect(controller.isLiked('a1'), isTrue);
    expect(controller.isCollected('a1'), isTrue);
    expect(controller.likeDelta('a1'), 1);

    await controller.hydrate('a1');
    expect(gateway.stateCalls, ['a1']);
  });

  test('a tap before hydration wins over the delayed state', () async {
    final gateway = _FakeGateway()
      ..state = const InteractionState(liked: true, collected: false);
    final controller = InteractionsController(gateway: gateway);

    final hydrate = controller.hydrate('a1');
    await controller.toggleLike('a1');
    await hydrate;
    expect(controller.isLiked('a1'), isTrue);
    expect(gateway.likeCalls, ['a1:1']);
  });

  test('hydrate stops probing after two failed state reads', () async {
    final gateway = _FakeGateway();
    final controller = InteractionsController(gateway: gateway);

    await controller.hydrate('a1');
    await controller.hydrate('a2');
    await controller.hydrate('a3');
    expect(gateway.stateCalls, ['a1', 'a2']);
  });

  test('hydrate is skipped when interactions are disabled', () async {
    final gateway = _FakeGateway();
    final controller = InteractionsController(gateway: gateway, enabled: false);

    await controller.hydrate('a1');
    expect(gateway.stateCalls, isEmpty);
  });

  test('disabled interactions do not call the gateway', () async {
    final gateway = _FakeGateway();
    final controller = InteractionsController(gateway: gateway, enabled: false);

    expect(await controller.toggleLike('a1'), '互动功能测试中，暂未开放');
    expect(await controller.toggleCollect('a1'), '互动功能测试中，暂未开放');
    expect(controller.isLiked('a1'), isFalse);
    expect(controller.isCollected('a1'), isFalse);
    expect(gateway.likeCalls, isEmpty);
    expect(gateway.collectCalls, isEmpty);
    controller.dispose();
  });

  test('duplicate taps while a request is in flight are ignored', () async {
    final gateway = _FakeGateway()..likeGate = Completer<void>();
    final controller = InteractionsController(gateway: gateway);

    final first = controller.toggleLike('a1');
    final second = controller.toggleLike('a1');
    expect(await second, isNull);
    expect(gateway.likeCalls, ['a1:1']);
    expect(controller.isLiked('a1'), isTrue);

    gateway.likeGate!.complete();
    expect(await first, isNull);
    controller.dispose();
  });
}
