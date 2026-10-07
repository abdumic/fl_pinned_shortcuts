import 'package:fl_pinned_shortcuts/fl_pinned_shortcuts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ImageSourceType contains supported sources', () {
    expect(ImageSourceType.values, contains(ImageSourceType.asset));
    expect(ImageSourceType.values, contains(ImageSourceType.network));
  });
}
