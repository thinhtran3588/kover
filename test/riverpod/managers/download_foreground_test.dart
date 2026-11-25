import 'package:flutter_test/flutter_test.dart';
import 'package:kover/riverpod/managers/download_manager/download_foreground.dart';

void main() {
  test('foregroundAction', () {
    expect(foregroundAction(active: 0, running: false), ForegroundAction.none);
    expect(foregroundAction(active: 2, running: false), ForegroundAction.start);
    expect(foregroundAction(active: 2, running: true), ForegroundAction.update);
    expect(foregroundAction(active: 0, running: true), ForegroundAction.stop);
  });
}
