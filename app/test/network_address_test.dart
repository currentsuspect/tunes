import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/reachability.dart';

void main() {
  test('loopback and link-local addresses cannot reach a server', () {
    expect(isRoutableAddress(InternetAddress('127.0.0.1')), isFalse);
    expect(isRoutableAddress(InternetAddress('::1')), isFalse);
    expect(isRoutableAddress(InternetAddress('fe80::1')), isFalse);
    expect(isRoutableAddress(InternetAddress('169.254.10.2')), isFalse);
  });

  test('a wi-fi or mobile address can', () {
    expect(isRoutableAddress(InternetAddress('192.168.100.15')), isTrue);
    expect(isRoutableAddress(InternetAddress('10.120.4.7')), isTrue);
    expect(isRoutableAddress(InternetAddress('2c0f:fe38::1')), isTrue);
  });

  test('no interfaces means no network, known without a ping', () async {
    expect(await hasNetworkAddress(list: () async => []), isFalse);
  });

  test('when interfaces cannot be listed, the ping decides', () async {
    expect(
      await hasNetworkAddress(list: () async => throw const OSError('no')),
      isTrue,
    );
  });
}
