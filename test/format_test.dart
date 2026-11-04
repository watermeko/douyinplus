import 'package:douyinplus/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatCount handles 万 and 亿', () {
    expect(formatCount(0), '0');
    expect(formatCount(999), '999');
    expect(formatCount(10633), '1.1万');
    expect(formatCount(10000), '1万');
    expect(formatCount(568554), '56.9万');
    expect(formatCount(100000000), '1亿');
  });

  test('formatTimer formats durations', () {
    expect(formatTimer(Duration.zero), '00:00');
    expect(formatTimer(const Duration(seconds: 65)), '01:05');
    expect(
      formatTimer(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });
}
