import 'package:fl_pinned_shortcuts/fl_pinned_shortcuts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ImageSourceType contains supported sources', () {
    expect(ImageSourceType.values, contains(ImageSourceType.asset));
    expect(ImageSourceType.values, contains(ImageSourceType.network));
  });

  test('unsupported platforms safely handle cache helpers', () async {
    expect(await FlutterPinnedShortcuts.isImageCached('https://example.com/a.png'), false);
    expect(await FlutterPinnedShortcuts.cacheNetworkImage('https://example.com/a.png'), isNull);
  });

  test('AdaptiveIconBackgroundType contains supported types', () {
    expect(
      AdaptiveIconBackgroundType.values,
      contains(AdaptiveIconBackgroundType.color),
    );
    expect(
      AdaptiveIconBackgroundType.values,
      contains(AdaptiveIconBackgroundType.image),
    );
  });
}
