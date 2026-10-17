import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/byte_ranges.dart';

void main() {
  test('runs merge when they touch or overlap', () {
    final r = ByteRanges()
      ..add(0, 10)
      ..add(20, 30)
      ..add(10, 20);
    expect(r.runEnd(0), 30);
    expect(r.length, 30);
    r.add(25, 40);
    expect(r.runEnd(5), 40);
  });

  test('a seek leaves a hole that is found and filled', () {
    final r = ByteRanges()
      ..add(0, 100)
      ..add(500, 600);
    expect(r.has(99), isTrue);
    expect(r.has(100), isFalse);
    expect(r.runEnd(550), 600);
    expect(r.firstGap(0, 1000), 100);
    expect(r.firstGap(500, 1000), 600);
    r.add(100, 500);
    r.add(600, 1000);
    expect(r.firstGap(0, 1000), isNull);
    expect(r.covers(1000), isTrue);
  });

  test('a byte that has not arrived is its own run end', () {
    final r = ByteRanges()..add(10, 20);
    expect(r.runEnd(5), 5);
    expect(r.runEnd(20), 20);
    expect(r.covers(20), isFalse);
  });

  test('runs added out of order stay sorted', () {
    final r = ByteRanges()
      ..add(80, 90)
      ..add(0, 5)
      ..add(40, 50);
    expect(r.firstGap(0, 100), 5);
    expect(r.firstGap(40, 100), 50);
    expect(r.firstGap(85, 90), isNull);
  });
}
