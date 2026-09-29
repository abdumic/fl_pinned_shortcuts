# fl_pinned_shortcuts

[![pub package](https://img.shields.io/pub/v/fl_pinned_shortcuts.svg)](https://pub.dev/packages/fl_pinned_shortcuts)
[![likes](https://img.shields.io/pub/likes/fl_pinned_shortcuts.svg)](https://pub.dev/packages/fl_pinned_shortcuts/score)
[![popularity](https://img.shields.io/pub/popularity/fl_pinned_shortcuts.svg)](https://pub.dev/packages/fl_pinned_shortcuts/score)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

`fl_pinned_shortcuts` is an Android-only Flutter plugin for creating and managing launcher pinned shortcuts with a simple Dart API.

It supports Flutter assets and network images, passes custom `extraData` when a shortcut is opened, handles both cold-start and warm-start clicks, checks shortcut support/pin state, and supports updating or disabling shortcuts.
| Screenshot 1 | Screenshot 2 | Screenshot 3 |
|--------------|--------------|--------------|
| ![Screenshot 1](https://github.com/abdumic/fl_pinned_shortcuts/blob/main/fl_pinned_shortcuts/Screenshot%202026-09-29%20145715.png) | ![Screenshot 2](https://github.com/abdumic/fl_pinned_shortcuts/blob/main/fl_pinned_shortcuts/Screenshot%202026-09-29%20145703.png) | ![Screenshot 3](https://github.com/abdumic/fl_pinned_shortcuts/blob/main/fl_pinned_shortcuts/Screenshot%202026-09-29%20145451.png) |


Network images are resolved through `flutter_cache_manager`, allowing the plugin to reuse the default cache used by `cached_network_image` when the same URL is already cached.

## Features

- Check whether the current Android launcher supports pinned shortcuts.
- Request a pinned shortcut from Flutter.
- Use Flutter asset images for shortcut icons.
- Use network images through `DefaultCacheManager`.
- Reuse the default `flutter_cache_manager` cache used by `cached_network_image`.
- Generate an Android adaptive bitmap icon from a single image by default.
- Optionally provide separate adaptive foreground and background layers.
- Pass JSON-compatible `extraData` with every shortcut.
- Receive shortcut clicks through `FlutterPinnedShortcuts.onShortcutClick`.
- Handle clicks when the app is launched from a terminated state or when it is already running.
- Check whether a specific shortcut is currently pinned.
- Update existing mutable shortcuts.
- Disable and re-enable shortcuts.
- No `MainActivity.kt` changes are required in the host application.
- No direct `http` dependency is added by this plugin.

## Platform support

This plugin currently supports **Android only**.

| Platform | Support |
| --- | --- |
| Android | ✅ |
| iOS | ❌ |
| Web | ❌ |
| macOS | ❌ |
| Windows | ❌ |
| Linux | ❌ |

Android pinned shortcuts were introduced in **Android 8.0 (API 26)**. The plugin can be included in apps with a lower `minSdk`, but `isSupported()` and shortcut creation return `false` when the platform or launcher does not support the feature.

## Requirements

- Flutter **3.44.0 or later**
- Dart **3.12.0 or later**
- Android SDK support for API 26+ for pinned-shortcut functionality

## Installation

Add the package with:

```bash
flutter pub add fl_pinned_shortcuts
```

Or add it manually to `pubspec.yaml`:

```yaml
dependencies:
  fl_pinned_shortcuts: ^0.1.2
```

Then run:

```bash
flutter pub get
```

## Quick start

Import the package:

```dart
import 'dart:async';

import 'package:fl_pinned_shortcuts/fl_pinned_shortcuts.dart';
```

Initialize the plugin once near your application root:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterPinnedShortcuts.initialize();

  runApp(const MyApp());
}
```

Listen for shortcut clicks once at your app/root-router level:

```dart
StreamSubscription<Map<String, dynamic>>? shortcutSubscription;

shortcutSubscription = FlutterPinnedShortcuts.onShortcutClick.listen((resultData) {
  final id = resultData['id'];
  final extraData = resultData['extraData'];

  debugPrint('Shortcut clicked: $id');
  debugPrint('extraData: $extraData');
});
```

Cancel the subscription when its owner is disposed:

```dart
@override
void dispose() {
  shortcutSubscription?.cancel();
  FlutterPinnedShortcuts.dispose();
  super.dispose();
}
```

> `dispose()` releases the plugin's event state. It does **not** remove shortcuts that the user has already pinned to the launcher.

## Check whether pinned shortcuts are supported

```dart
final supported = await FlutterPinnedShortcuts.isSupported();

if (supported) {
  debugPrint('Pinned shortcuts are supported.');
} else {
  debugPrint('Pinned shortcuts are not supported.');
}
```

The result depends on both the Android version and the current default launcher.

## Create a shortcut with one image

For most apps, especially when the image is a **reciter photo or other artwork**, use a single image:

```dart
await FlutterPinnedShortcuts.createPinnedShortcut(
  id: 'reciter_1',
  label: 'Mishary Alafasy',
  imageSource: 'assets/reciters/mishary.png',
  imageSourceType: ImageSourceType.asset,
  longLabel: 'Listen to Mishary Alafasy',
  extraData: const {
    'reciterId': '1',
  },
);
```

The plugin uses the image as the adaptive foreground by default, so you do **not** need to provide three separate images just to create a shortcut.

### Non-square images

The source image does not have to be square. The plugin scales the image into the adaptive icon foreground while Android's launcher applies its own icon mask and display rules.

For photographic artwork where preserving the full image is important, a single source image is the simplest option.

If you need precise adaptive foreground/background composition, use the advanced adaptive-icon API described below.

## Create a shortcut from a network image

```dart
await FlutterPinnedShortcuts.createPinnedShortcut(
  id: 'reciter_1',
  label: 'Mishary Alafasy',
  imageSource: 'https://example.com/reciters/mishary.png',
  imageSourceType: ImageSourceType.network,
  longLabel: 'Listen to Mishary Alafasy',
  extraData: const {
    'reciterId': '1',
  },
);
```

### Network image caching

Network images are resolved using:

```dart
DefaultCacheManager().getSingleFile(url)
```

This is intentional. `cached_network_image` uses `flutter_cache_manager` for its default network image cache. When both your app and `fl_pinned_shortcuts` use the default cache manager, the plugin can reuse a file that has already been cached for the same URL instead of downloading it again.

For example, if your app already displays a reciter image with:

```dart
CachedNetworkImage(
  imageUrl: reciter.imageUrl,
)
```

the shortcut can use the same URL:

```dart
await FlutterPinnedShortcuts.createPinnedShortcut(
  id: 'reciter_1',
  label: reciter.name,
  imageSource: reciter.imageUrl,
  imageSourceType: ImageSourceType.network,
);
```

This shared-cache behavior assumes both use the default `flutter_cache_manager` configuration. A custom cache manager or a different cache configuration may use a different cache location.

## Adaptive icon layers

A single `imageSource` is enough for most use cases.

For designs where the foreground and background must be controlled separately, provide adaptive-icon layers:

```dart
await FlutterPinnedShortcuts.createPinnedShortcut(
  id: 'custom_shortcut',
  label: 'My Shortcut',
  imageSource: 'assets/icon.png',
  imageSourceType: ImageSourceType.asset,
  adaptiveIconForeground: 'assets/icon_foreground.png',
  adaptiveIconForegroundType: ImageSourceType.asset,
  adaptiveIconBackground: 'assets/icon_background.png',
  adaptiveIconBackgroundType: AdaptiveIconBackgroundType.image,
);
```

A solid color can be used instead of an image background:

```dart
await FlutterPinnedShortcuts.createPinnedShortcut(
  id: 'blue_shortcut',
  label: 'Blue Shortcut',
  imageSource: 'assets/icon.png',
  imageSourceType: ImageSourceType.asset,
  adaptiveIconBackground: '#2196F3',
  adaptiveIconBackgroundType: AdaptiveIconBackgroundType.color,
);
```

The adaptive foreground size can be adjusted with `adaptiveIconForegroundScale`:

```dart
await FlutterPinnedShortcuts.createPinnedShortcut(
  id: 'large_foreground',
  label: 'Large Foreground',
  imageSource: 'assets/icon.png',
  imageSourceType: ImageSourceType.asset,
  adaptiveIconForegroundScale: 0.85,
);
```

`adaptiveIconForegroundScale` must be greater than `0` and less than or equal to `1`. The default is `0.72`.

## Asset requirements

When using `ImageSourceType.asset`, the image must be available to the host application through its `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/reciters/mishary.png
    - assets/icon.png
```

Then reference the exact asset path from Dart.

## Handle shortcut clicks

The click stream emits a map with this structure:

```dart
{
  'id': 'reciter_1',
  'extraData': {
    'reciterId': '1',
  },
}
```

Example:

```dart
FlutterPinnedShortcuts.onShortcutClick.listen((resultData) {
  final id = resultData['id'] as String?;
  final extraData = resultData['extraData'] as Map?;

  switch (id) {
    case 'reciter_1':
      // Navigate to the reciter page.
      break;

    case 'radio':
      // Navigate to Quran Radio.
      break;
  }

  debugPrint('Shortcut: $id');
  debugPrint('Data: $extraData');
});
```

The plugin handles both:

- **Cold start:** the app is not running and is launched from the shortcut.
- **Warm start:** the app is already running and the shortcut launches a new activity intent.

## Pass extra data

`extraData` is useful for opening a specific feature, reciter, page, or item:

```dart
await FlutterPinnedShortcuts.createPinnedShortcut(
  id: 'reciter_23',
  label: 'Abdul Basit',
  imageSource: reciter.imageUrl,
  imageSourceType: ImageSourceType.network,
  extraData: const {
    'type': 'reciter',
    'reciterId': '23',
  },
);
```

Use JSON-compatible values such as:

- `String`
- `num`
- `bool`
- `null`
- `List`
- `Map` with JSON-compatible keys and values

Do not place secrets, tokens, passwords, or private information in `extraData`. Shortcut metadata is handled by Android and may be visible to the launcher.

## Check whether a shortcut is pinned

```dart
final isPinned = await FlutterPinnedShortcuts.isPinned('reciter_23');

if (isPinned) {
  debugPrint('Shortcut is pinned.');
}
```

## Update a pinned shortcut

Pinned shortcuts can be updated using the same ID:

```dart
await FlutterPinnedShortcuts.updatePinnedShortcut(
  id: 'reciter_23',
  label: 'Abdul Basit',
  imageSource: updatedReciterImageUrl,
  imageSourceType: ImageSourceType.network,
  longLabel: 'Listen to Abdul Basit',
  extraData: const {
    'type': 'reciter',
    'reciterId': '23',
  },
);
```

The shortcut must be mutable for Android to allow the update.

## Disable and re-enable a shortcut

You can disable a shortcut without removing it from the launcher:

```dart
await FlutterPinnedShortcuts.disablePinnedShortcut(
  'reciter_23',
  disabledMessage: 'This reciter is currently unavailable.',
);
```

Re-enable it later:

```dart
await FlutterPinnedShortcuts.enablePinnedShortcut('reciter_23');
```

## Removing a pinned shortcut

Android does not allow an application to silently remove a shortcut that the user pinned to the launcher.

For that reason:

```dart
final removed =
    await FlutterPinnedShortcuts.removePinnedShortcut('reciter_23');
```

may return `false` on modern Android. The user can remove the pinned shortcut from their launcher.

Use `disablePinnedShortcut()` when the goal is to make an existing shortcut unavailable without asking the user to remove it manually.

## Complete example

```dart
import 'dart:async';

import 'package:fl_pinned_shortcuts/fl_pinned_shortcuts.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterPinnedShortcuts.initialize();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<Map<String, dynamic>>? _shortcutSubscription;
  bool _supported = false;

  @override
  void initState() {
    super.initState();

    _shortcutSubscription =
        FlutterPinnedShortcuts.onShortcutClick.listen((data) {
      final id = data['id'];
      final extraData = data['extraData'];

      debugPrint('Shortcut clicked: $id');
      debugPrint('extraData: $extraData');

      // Navigate based on id/extraData here.
    });

    _loadSupport();
  }

  Future<void> _loadSupport() async {
    final supported = await FlutterPinnedShortcuts.isSupported();

    if (!mounted) return;
    setState(() => _supported = supported);
  }

  Future<void> _pinReciter() async {
    await FlutterPinnedShortcuts.createPinnedShortcut(
      id: 'reciter_1',
      label: 'Mishary Alafasy',
      imageSource: 'assets/reciters/mishary.png',
      imageSourceType: ImageSourceType.asset,
      longLabel: 'Listen to Mishary Alafasy',
      extraData: const {
        'type': 'reciter',
        'reciterId': '1',
      },
    );
  }

  @override
  void dispose() {
    _shortcutSubscription?.cancel();
    FlutterPinnedShortcuts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Pinned shortcuts'),
        ),
        body: Center(
          child: FilledButton.icon(
            onPressed: _supported ? _pinReciter : null,
            icon: const Icon(Icons.push_pin_outlined),
            label: const Text('Pin reciter'),
          ),
        ),
      ),
    );
  }
}
```

## Error handling

Invalid arguments such as an empty shortcut ID, empty label, or invalid adaptive foreground scale throw a Dart `ArgumentError`.

Native Android failures are returned through Flutter platform errors. Wrap calls in `try/catch` when your app needs to show a user-facing error:

```dart
try {
  final created = await FlutterPinnedShortcuts.createPinnedShortcut(
    id: 'radio',
    label: 'Quran Radio',
    imageSource: radioImageUrl,
    imageSourceType: ImageSourceType.network,
  );

  debugPrint('Pin request sent: $created');
} catch (error) {
  debugPrint('Unable to create shortcut: $error');
}
```

## Why this package does not depend on `http`

This plugin intentionally does not add a direct `http` dependency.

Network images are loaded through `flutter_cache_manager`, which owns the HTTP/cache implementation. This avoids the older dependency chain used by packages that require `http 0.13.x` and makes the plugin easier to use alongside current versions of `cached_network_image`.

## Android integration

No changes to the host application's `MainActivity.kt` are required.

The plugin uses Flutter's Android plugin lifecycle (`ActivityAware`) and receives activity `onNewIntent` callbacks internally. This also allows it to work with host activities that are subclasses of `AudioServiceActivity`.

## Important Android behavior

### The user confirms the pin

Calling `createPinnedShortcut()` requests the Android system pin flow. The launcher/user decides whether the shortcut is actually placed on the home screen.

### Launcher support varies

Different launchers may display shortcut icons differently and may apply their own icon masks, scaling, and safe areas. The plugin generates an adaptive bitmap icon, but it cannot force every launcher to render an identical shape or size.

### Pinning is user-controlled

Applications cannot silently remove shortcuts that the user pinned. This is an Android platform restriction.

## Performance and cache notes

- Network shortcut icons are resolved asynchronously before the Android pin request is sent.
- Large images are decoded and scaled natively to limit memory usage.
- Reusing the default cache manager can avoid downloading the same network image more than once.
- For frequently changing remote images, update the pinned shortcut when your app refreshes its reciter artwork.

## API reference

### `FlutterPinnedShortcuts.initialize()`

Initializes the plugin and lets the native side process the current launch intent. Safe to call more than once.

### `FlutterPinnedShortcuts.isSupported()`

Returns whether pinned shortcuts are currently supported by the Android platform and default launcher.

### `FlutterPinnedShortcuts.createPinnedShortcut(...)`

Requests a new pinned shortcut.

Parameters include:

- `id` — unique shortcut ID.
- `label` — short launcher label.
- `imageSource` — asset path or URL.
- `imageSourceType` — `asset` or `network`.
- `longLabel` — optional longer launcher label.
- `extraData` — optional JSON-compatible data.
- `adaptiveIconForeground` — optional separate foreground image.
- `adaptiveIconForegroundType` — source type of the foreground image.
- `adaptiveIconBackground` — optional color or image background.
- `adaptiveIconBackgroundType` — `color` or `image`.
- `adaptiveIconForegroundScale` — foreground size, default `0.72`.

### `FlutterPinnedShortcuts.onShortcutClick`

Broadcast stream of shortcut click data:

```dart
{
  'id': String,
  'extraData': dynamic,
}
```

### `FlutterPinnedShortcuts.isPinned(id)`

Returns whether Android currently reports the specified shortcut as pinned.

### `FlutterPinnedShortcuts.updatePinnedShortcut(...)`

Updates an existing mutable shortcut.

### `FlutterPinnedShortcuts.disablePinnedShortcut(...)`

Disables a shortcut while keeping it present on the launcher.

### `FlutterPinnedShortcuts.enablePinnedShortcut(id)`

Re-enables a previously disabled shortcut.

### `FlutterPinnedShortcuts.removePinnedShortcut(id)`

Attempts to remove a pinned shortcut. On modern Android this normally returns `false` because user-pinned shortcuts cannot be silently removed by the application.

### `FlutterPinnedShortcuts.dispose()`

Releases the plugin's event state. It does not uninstall or remove shortcuts from the launcher.

## Development

Clone the repository, install Flutter, and run the example application:

```bash
flutter pub get
cd example
flutter pub get
flutter run
```

Run tests from the package root:

```bash
flutter test
```

## Contributing

Issues, bug reports, documentation improvements, and pull requests are welcome.

When reporting an Android shortcut issue, include:

- Android version
- device/launcher name
- Flutter version
- plugin version
- whether the app was running or terminated when the shortcut was tapped

## License

This package is released under the [MIT License](LICENSE).
