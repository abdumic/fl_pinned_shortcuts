import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Identifies where the shortcut icon should be loaded from.
enum ImageSourceType {
  /// A Flutter asset declared in the host application's pubspec.yaml.
  asset,

  /// A network image URL resolved through DefaultCacheManager.
  network,
}

/// Selects how an adaptive-icon background is created.
enum AdaptiveIconBackgroundType {
  /// [adaptiveIconBackground] is a hex color such as `#2196F3`.
  color,

  /// [adaptiveIconBackground] is an asset or network image.
  image,
}

/// Creates and manages Android launcher pinned shortcuts.
///
/// Android pinned shortcuts are available on Android 8.0 (API 26) and above,
/// and the device's default launcher must support in-app pin requests.
///
/// Network images intentionally use [DefaultCacheManager]. This is the same
/// cache-manager mechanism used by `cached_network_image`, so a URL that has
/// already been cached can be reused instead of being downloaded again.
///
/// Shortcut icons are generated as Android adaptive bitmap icons to avoid the
/// extra launcher padding commonly applied to legacy bitmap shortcuts.
class FlutterPinnedShortcuts {
  FlutterPinnedShortcuts._();

  static const MethodChannel _methodChannel =
      MethodChannel('fl_pinned_shortcuts/methods');

  static const EventChannel _eventChannel =
      EventChannel('fl_pinned_shortcuts/events');

  static Stream<Map<String, dynamic>>? _shortcutClickStream;

  /// Initializes the plugin and lets the native side re-check the current
  /// launch Intent. Calling this more than once is safe.
  static Future<void> initialize() async {
    if (!_isAndroid) return;

    try {
      await _methodChannel.invokeMethod<void>('initialize');
    } on MissingPluginException {
      // Gracefully ignore platforms where the Android plugin is unavailable.
    } on PlatformException {
      // A plugin/platform setup problem should not crash application startup.
    }
  }

  /// Emits every time a pinned shortcut launches the Flutter activity.
  ///
  /// The event has this shape:
  ///
  /// ```dart
  /// {
  ///   'id': 'asset_shortcut',
  ///   'extraData': {'source': 'asset'},
  /// }
  /// ```
  ///
  /// Subscribe once near the app/root-router level. The native plugin keeps
  /// a pending cold-start event until a listener attaches.
  static Stream<Map<String, dynamic>> get onShortcutClick {
    if (!_isAndroid) {
      return const Stream<Map<String, dynamic>>.empty();
    }

    return _shortcutClickStream ??= _eventChannel
        .receiveBroadcastStream()
        .map<Map<String, dynamic>>((dynamic event) {
      final raw = Map<Object?, Object?>.from(event as Map);

      final extraDataValue = raw['extraData'];
      dynamic extraData;

      if (extraDataValue is String && extraDataValue.isNotEmpty) {
        try {
          extraData = jsonDecode(extraDataValue);
        } catch (_) {
          extraData = null;
        }
      }

      return <String, dynamic>{
        'id': raw['id'],
        'extraData': extraData,
      };
    });
  }

  /// Returns whether the current default launcher supports pinned shortcuts.
  static Future<bool> isSupported() async {
    if (!_isAndroid) return false;

    try {
      final result = await _methodChannel.invokeMethod<bool>('isSupported');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Creates a new pinned shortcut and asks the launcher to show its system
  /// confirmation UI.
  ///
  /// [imageSource] is kept as the legacy/base icon source. When adaptive-icon
  /// layers are not supplied, it is automatically used as the foreground of an
  /// adaptive bitmap so launchers do not apply the excessive legacy-icon
  /// padding that can make shortcut icons look tiny.
  ///
  /// [adaptiveIconForeground] optionally replaces [imageSource] as the
  /// adaptive foreground. If [adaptiveIconForegroundType] is omitted, the
  /// foreground uses [imageSourceType].
  ///
  /// For [AdaptiveIconBackgroundType.color], [adaptiveIconBackground] should
  /// be a color such as `#2196F3` or `#FF2196F3`. For
  /// [AdaptiveIconBackgroundType.image], it should be an asset path or URL.
  static Future<bool> createPinnedShortcut({
    required String id,
    required String label,
    required String imageSource,
    required ImageSourceType imageSourceType,
    String? longLabel,
    Map<String, dynamic>? extraData,
    String? adaptiveIconForeground,
    ImageSourceType? adaptiveIconForegroundType,
    String? adaptiveIconBackground,
    AdaptiveIconBackgroundType adaptiveIconBackgroundType =
        AdaptiveIconBackgroundType.color,
    double adaptiveIconForegroundScale = 0.72,
  }) async {
    _validateString(id, 'id');
    _validateString(label, 'label');
    _validateString(imageSource, 'imageSource');
    _validateForegroundScale(adaptiveIconForegroundScale);

    if (!await isSupported()) return false;

    final baseImage = await _resolveImage(
      imageSource: imageSource,
      imageSourceType: imageSourceType,
    );

    final foregroundSource = adaptiveIconForeground ?? imageSource;
    final foregroundType =
        adaptiveIconForegroundType ?? imageSourceType;
    final foregroundImage = adaptiveIconForeground == null
        ? baseImage
        : await _resolveImage(
            imageSource: foregroundSource,
            imageSourceType: foregroundType,
          );

    String? backgroundImagePath;
    if (adaptiveIconBackgroundType == AdaptiveIconBackgroundType.image) {
      if (adaptiveIconBackground == null ||
          adaptiveIconBackground.trim().isEmpty) {
        throw ArgumentError.value(
          adaptiveIconBackground,
          'adaptiveIconBackground',
          'is required when adaptiveIconBackgroundType is image',
        );
      }

      final backgroundImage = await _resolveImage(
        imageSource: adaptiveIconBackground,
        imageSourceType: imageSourceType,
      );
      backgroundImagePath = backgroundImage.path;
    }

    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'createPinnedShortcut',
        <String, dynamic>{
          'id': id,
          'label': label,
          'longLabel': longLabel,
          'imageType': baseImage.type,
          'imagePath': baseImage.path,
          'extraData': extraData == null ? null : jsonEncode(extraData),
          'adaptiveIconForegroundType': foregroundImage.type,
          'adaptiveIconForegroundPath': foregroundImage.path,
          'adaptiveIconBackgroundType':
              adaptiveIconBackgroundType.name,
          'adaptiveIconBackgroundPath': backgroundImagePath,
          'adaptiveIconBackgroundColor':
              adaptiveIconBackgroundType == AdaptiveIconBackgroundType.color
                  ? adaptiveIconBackground
                  : null,
          'adaptiveIconForegroundScale': adaptiveIconForegroundScale,
        },
      );

      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Updates an existing mutable pinned shortcut with the same [id].
  ///
  /// The adaptive-icon options mirror [createPinnedShortcut].
  static Future<bool> updatePinnedShortcut({
    required String id,
    required String label,
    required String imageSource,
    required ImageSourceType imageSourceType,
    String? longLabel,
    Map<String, dynamic>? extraData,
    String? adaptiveIconForeground,
    ImageSourceType? adaptiveIconForegroundType,
    String? adaptiveIconBackground,
    AdaptiveIconBackgroundType adaptiveIconBackgroundType =
        AdaptiveIconBackgroundType.color,
    double adaptiveIconForegroundScale = 0.72,
  }) async {
    _validateString(id, 'id');
    _validateString(label, 'label');
    _validateString(imageSource, 'imageSource');
    _validateForegroundScale(adaptiveIconForegroundScale);

    if (!await isSupported()) return false;

    final baseImage = await _resolveImage(
      imageSource: imageSource,
      imageSourceType: imageSourceType,
    );

    final foregroundSource = adaptiveIconForeground ?? imageSource;
    final foregroundType =
        adaptiveIconForegroundType ?? imageSourceType;
    final foregroundImage = adaptiveIconForeground == null
        ? baseImage
        : await _resolveImage(
            imageSource: foregroundSource,
            imageSourceType: foregroundType,
          );

    String? backgroundImagePath;
    if (adaptiveIconBackgroundType == AdaptiveIconBackgroundType.image) {
      if (adaptiveIconBackground == null ||
          adaptiveIconBackground.trim().isEmpty) {
        throw ArgumentError.value(
          adaptiveIconBackground,
          'adaptiveIconBackground',
          'is required when adaptiveIconBackgroundType is image',
        );
      }

      final backgroundImage = await _resolveImage(
        imageSource: adaptiveIconBackground,
        imageSourceType: imageSourceType,
      );
      backgroundImagePath = backgroundImage.path;
    }

    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'updatePinnedShortcut',
        <String, dynamic>{
          'id': id,
          'label': label,
          'longLabel': longLabel,
          'imageType': baseImage.type,
          'imagePath': baseImage.path,
          'extraData': extraData == null ? null : jsonEncode(extraData),
          'adaptiveIconForegroundType': foregroundImage.type,
          'adaptiveIconForegroundPath': foregroundImage.path,
          'adaptiveIconBackgroundType':
              adaptiveIconBackgroundType.name,
          'adaptiveIconBackgroundPath': backgroundImagePath,
          'adaptiveIconBackgroundColor':
              adaptiveIconBackgroundType == AdaptiveIconBackgroundType.color
                  ? adaptiveIconBackground
                  : null,
          'adaptiveIconForegroundScale': adaptiveIconForegroundScale,
        },
      );

      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Returns whether [url] is currently available in the shared disk cache.
  ///
  /// This method is cache-only: it never performs a network request. A
  /// cached entry may still be returned even when its cache-manager policy
  /// considers the entry stale, which is useful when the device is offline
  /// and an existing image is still perfectly usable for a shortcut icon.
  static Future<bool> isImageCached(String url) async {
    _validateString(url, 'url');

    if (!_isAndroid) return false;

    try {
      final cached = await DefaultCacheManager().getFileFromCache(url);
      return cached?.file.existsSync() ?? false;
    } on Exception {
      return false;
    }
  }

  /// Ensures [url] is available in the shared disk cache.
  ///
  /// Returns the cached file when one exists, otherwise downloads and caches
  /// the image using [DefaultCacheManager]. This is useful for apps that want
  /// to prepare shortcut images while the device is online so they can later
  /// create shortcuts while offline.
  static Future<String?> cacheNetworkImage(String url) async {
    _validateString(url, 'url');

    if (!_isAndroid) return null;

    try {
      final cacheManager = DefaultCacheManager();
      final cached = await cacheManager.getFileFromCache(url);
      if (cached != null && cached.file.existsSync()) {
        return cached.file.path;
      }

      final file = await cacheManager.getSingleFile(url);
      return file.path;
    } on Exception {
      return null;
    }
  }

  /// Returns true when Android currently reports the [id] as pinned.
  static Future<bool> isPinned(String id) async {
    _validateString(id, 'id');
    if (!_isAndroid) return false;

    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'isPinned',
        <String, dynamic>{'id': id},
      );

      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Disables a pinned shortcut.
  ///
  /// Android does not allow an app to silently unpin a user-created pinned
  /// shortcut. For that reason this package intentionally does not fake a
  /// remove operation. Use this method when you need the shortcut to remain on
  /// the launcher but become unavailable, with [disabledMessage] shown by the
  /// launcher where supported.
  static Future<bool> disablePinnedShortcut(
    String id, {
    String? disabledMessage,
  }) async {
    _validateString(id, 'id');
    if (!_isAndroid) return false;

    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'disablePinnedShortcut',
        <String, dynamic>{
          'id': id,
          'disabledMessage': disabledMessage,
        },
      );

      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Re-enables a previously disabled pinned shortcut.
  static Future<bool> enablePinnedShortcut(String id) async {
    _validateString(id, 'id');
    if (!_isAndroid) return false;

    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'enablePinnedShortcut',
        <String, dynamic>{'id': id},
      );

      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Attempts to remove a pinned shortcut.
  ///
  /// On modern Android this returns `false` because apps cannot remove
  /// user-pinned shortcuts. The user can remove them from the launcher.
  static Future<bool> removePinnedShortcut(String id) async {
    _validateString(id, 'id');
    if (!_isAndroid) return false;

    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'removePinnedShortcut',
        <String, dynamic>{'id': id},
      );

      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Releases the Dart-side/native event state owned by this plugin instance.
  ///
  /// The plugin itself remains available to the Flutter engine, so later calls
  /// to [initialize] and [onShortcutClick] remain valid.
  static Future<void> dispose() async {
    if (_isAndroid) {
      try {
        await _methodChannel.invokeMethod<void>('dispose');
      } on MissingPluginException {
        // Safe no-op on unsupported platforms.
      } on PlatformException {
        // Safe no-op if the native plugin is unavailable.
      }
    }

    _shortcutClickStream = null;
  }

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void _validateForegroundScale(double value) {
    if (value <= 0 || value > 1) {
      throw ArgumentError.value(
        value,
        'adaptiveIconForegroundScale',
        'must be > 0 and <= 1',
      );
    }
  }

  static Future<_ResolvedImage> _resolveImage({
    required String imageSource,
    required ImageSourceType imageSourceType,
  }) async {
    switch (imageSourceType) {
      case ImageSourceType.asset:
        return _ResolvedImage(type: 'asset', path: imageSource);
      case ImageSourceType.network:
        final cacheManager = DefaultCacheManager();

        // Important for offline shortcut creation:
        // getSingleFile() may try the network when no fresh cache entry is
        // available. getFileFromCache() is cache-only and can reuse an older
        // disk-cached image without any network connection.
        final cached = await cacheManager.getFileFromCache(imageSource);
        if (cached != null && cached.file.existsSync()) {
          return _ResolvedImage(type: 'file', path: cached.file.path);
        }

        final file = await cacheManager.getSingleFile(imageSource);
        return _ResolvedImage(type: 'file', path: file.path);
    }
  }

  static void _validateString(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
  }
}

class _ResolvedImage {
  const _ResolvedImage({required this.type, required this.path});

  final String type;
  final String path;
}
