package com.hudasoft.fl_pinned_shortcuts

import android.app.Activity
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.drawable.Icon
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.io.InputStream

class FlPinnedShortcutsPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.NewIntentListener {

    companion object {
        private const val METHOD_CHANNEL = "fl_pinned_shortcuts/methods"
        private const val EVENT_CHANNEL = "fl_pinned_shortcuts/events"
        private const val EXTRA_SHORTCUT_ID = "fl_pinned_shortcuts.id"
        private const val EXTRA_DATA = "fl_pinned_shortcuts.extra_data"
        private const val MAX_ICON_DIMENSION = 512
    }

    private var appContext: android.content.Context? = null
    private var flutterAssets: FlutterPlugin.FlutterAssets? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingShortcutEvent: Map<String, Any?>? = null
    private var lastHandledIntent: Intent? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        flutterAssets = binding.flutterAssets

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detachFromActivity()

        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        eventSink = null
        pendingShortcutEvent = null
        lastHandledIntent = null
        flutterAssets = null
        appContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addOnNewIntentListener(this)
        handleShortcutIntent(binding.activity.intent)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachFromActivity()
    }

    override fun onNewIntent(intent: Intent): Boolean {
        handleShortcutIntent(intent)
        return false
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                activity?.intent?.let(::handleShortcutIntent)
                result.success(null)
            }

            "isSupported" -> result.success(isSupported())

            "createPinnedShortcut" -> {
                handleCreateOrUpdate(call, result, update = false)
            }

            "updatePinnedShortcut" -> {
                handleCreateOrUpdate(call, result, update = true)
            }

            "isPinned" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    result.success(false)
                    return
                }

                val id = call.argument<String>("id")
                if (id.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "id is required", null)
                    return
                }

                result.success(
                    try {
                        getShortcutManager().pinnedShortcuts.any { it.id == id }
                    } catch (_: IllegalStateException) {
                        false
                    }
                )
            }

            "disablePinnedShortcut" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    result.success(false)
                    return
                }

                val id = call.argument<String>("id")
                if (id.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "id is required", null)
                    return
                }

                try {
                    val message = call.argument<String>("disabledMessage")
                    getShortcutManager().disableShortcuts(
                        listOf(id),
                        message
                    )
                    result.success(true)
                } catch (error: IllegalArgumentException) {
                    result.error(
                        "SHORTCUT_ERROR",
                        error.message,
                        null
                    )
                } catch (error: IllegalStateException) {
                    result.error(
                        "SHORTCUT_ERROR",
                        error.message,
                        null
                    )
                }
            }

            "enablePinnedShortcut" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    result.success(false)
                    return
                }

                val id = call.argument<String>("id")
                if (id.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "id is required", null)
                    return
                }

                try {
                    getShortcutManager().enableShortcuts(listOf(id))
                    result.success(true)
                } catch (error: IllegalArgumentException) {
                    result.error(
                        "SHORTCUT_ERROR",
                        error.message,
                        null
                    )
                } catch (error: IllegalStateException) {
                    result.error(
                        "SHORTCUT_ERROR",
                        error.message,
                        null
                    )
                }
            }

            "removePinnedShortcut" -> {
                // Android intentionally does not expose an app API to unpin a
                // user-created launcher shortcut. Returning false is honest and
                // avoids pretending that disableShortcuts() removes it.
                result.success(false)
            }

            "dispose" -> {
                eventSink = null
                pendingShortcutEvent = null
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        val pending = pendingShortcutEvent
        if (events != null && pending != null) {
            events.success(pending)
            pendingShortcutEvent = null
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun isSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false

        return try {
            getShortcutManager().isRequestPinShortcutSupported
        } catch (_: Exception) {
            false
        }
    }

    private fun getShortcutManager(): ShortcutManager {
        return requireNotNull(
            appContext?.getSystemService(ShortcutManager::class.java)
        )
    }

    private fun handleCreateOrUpdate(
        call: MethodCall,
        result: MethodChannel.Result,
        update: Boolean,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(false)
            return
        }

        val id = call.argument<String>("id")
        val label = call.argument<String>("label")
        val longLabel = call.argument<String>("longLabel")
        val imageType = call.argument<String>("imageType")
        val imagePath = call.argument<String>("imagePath")
        val extraData = call.argument<String>("extraData")
        val adaptiveForegroundType =
            call.argument<String>("adaptiveIconForegroundType")
        val adaptiveForegroundPath =
            call.argument<String>("adaptiveIconForegroundPath")
        val adaptiveBackgroundType =
            call.argument<String>("adaptiveIconBackgroundType")
        val adaptiveBackgroundPath =
            call.argument<String>("adaptiveIconBackgroundPath")
        val adaptiveBackgroundColor =
            call.argument<String>("adaptiveIconBackgroundColor")
        val adaptiveForegroundScale =
            call.argument<Double>("adaptiveIconForegroundScale") ?: 0.72

        if (id.isNullOrBlank() || label.isNullOrBlank()) {
            result.error(
                "INVALID_ARGUMENT",
                "id and label are required",
                null
            )
            return
        }

        if (imageType.isNullOrBlank() || imagePath.isNullOrBlank()) {
            result.error(
                "INVALID_IMAGE",
                "imagePath and imageType are required",
                null
            )
            return
        }

        try {
            val iconBitmap = loadBitmap(imageType, imagePath)
            if (iconBitmap == null) {
                result.error(
                    "INVALID_IMAGE",
                    "Could not decode shortcut image",
                    null
                )
                return
            }

            val shortcut = buildShortcut(
                id = id,
                label = label,
                longLabel = longLabel,
                legacyBitmap = iconBitmap,
                adaptiveForegroundType = adaptiveForegroundType,
                adaptiveForegroundPath = adaptiveForegroundPath,
                adaptiveBackgroundType = adaptiveBackgroundType,
                adaptiveBackgroundPath = adaptiveBackgroundPath,
                adaptiveBackgroundColor = adaptiveBackgroundColor,
                adaptiveForegroundScale = adaptiveForegroundScale,
                extraData = extraData
            )

            val success = if (update) {
                getShortcutManager().updateShortcuts(listOf(shortcut))
            } else {
                if (!isSupported()) {
                    false
                } else {
                    getShortcutManager().requestPinShortcut(shortcut, null)
                }
            }

            result.success(success)
        } catch (error: Exception) {
            result.error(
                "SHORTCUT_ERROR",
                error.message ?: error.javaClass.simpleName,
                null
            )
        }
    }

    private fun buildShortcut(
        id: String,
        label: String,
        longLabel: String?,
        legacyBitmap: Bitmap,
        adaptiveForegroundType: String?,
        adaptiveForegroundPath: String?,
        adaptiveBackgroundType: String?,
        adaptiveBackgroundPath: String?,
        adaptiveBackgroundColor: String?,
        adaptiveForegroundScale: Double,
        extraData: String?,
    ): ShortcutInfo {
        val context = requireNotNull(appContext)

        val launchIntent = createLaunchIntent().apply {
            putExtra(EXTRA_SHORTCUT_ID, id)
            if (extraData != null) {
                putExtra(EXTRA_DATA, extraData)
            } else {
                removeExtra(EXTRA_DATA)
            }
            addFlags(
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
        }

        val icon = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val foreground = if (!adaptiveForegroundType.isNullOrBlank() &&
                !adaptiveForegroundPath.isNullOrBlank()
            ) {
                loadBitmap(adaptiveForegroundType, adaptiveForegroundPath)
            } else {
                legacyBitmap
            } ?: throw IllegalArgumentException(
                "Could not decode adaptive icon foreground"
            )

            val background = when (adaptiveBackgroundType) {
                "image" -> {
                    if (adaptiveBackgroundPath.isNullOrBlank()) {
                        throw IllegalArgumentException(
                            "adaptiveIconBackgroundPath is required for image background"
                        )
                    }
                    loadBitmap("file", adaptiveBackgroundPath)
                        ?: throw IllegalArgumentException(
                            "Could not decode adaptive icon background"
                        )
                }
                "color", null, "" -> null
                else -> throw IllegalArgumentException(
                    "Unsupported adaptiveIconBackgroundType: $adaptiveBackgroundType"
                )
            }

            val backgroundColor = if (adaptiveBackgroundType == "color") {
                parseColor(adaptiveBackgroundColor)
            } else {
                null
            }

            val adaptiveBitmap = composeAdaptiveIcon(
                foreground = foreground,
                background = background,
                backgroundColor = backgroundColor,
                foregroundScale = adaptiveForegroundScale,
            )

            Icon.createWithAdaptiveBitmap(adaptiveBitmap)
        } else {
            Icon.createWithBitmap(legacyBitmap)
        }

        return ShortcutInfo.Builder(context, id)
            .setShortLabel(label)
            .apply {
                if (!longLabel.isNullOrBlank()) {
                    setLongLabel(longLabel)
                }
            }
            .setIcon(icon)
            .setIntent(launchIntent)
            .build()
    }

    private fun composeAdaptiveIcon(
        foreground: Bitmap,
        background: Bitmap?,
        backgroundColor: Int?,
        foregroundScale: Double,
    ): Bitmap {
        val canvasSize = maxOf(
            432,
            foreground.width,
            foreground.height,
            background?.width ?: 0,
            background?.height ?: 0,
        )
        val output = Bitmap.createBitmap(
            canvasSize,
            canvasSize,
            Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(output)

        if (background != null) {
            drawCenterCrop(canvas, background, canvasSize, canvasSize)
        } else if (backgroundColor != null) {
            canvas.drawColor(backgroundColor)
        } else {
            canvas.drawColor(Color.TRANSPARENT)
        }

        val safeSize = (canvasSize * foregroundScale)
            .toInt()
            .coerceAtLeast(1)
        val scale = minOf(
            safeSize.toFloat() / foreground.width.toFloat(),
            safeSize.toFloat() / foreground.height.toFloat(),
        )
        val width = (foreground.width * scale)
            .toInt()
            .coerceAtLeast(1)
        val height = (foreground.height * scale)
            .toInt()
            .coerceAtLeast(1)
        val left = (canvasSize - width) / 2
        val top = (canvasSize - height) / 2

        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        canvas.drawBitmap(
            foreground,
            null,
            Rect(
                left,
                top,
                left + width,
                top + height,
            ),
            paint,
        )

        return output
    }

    private fun drawCenterCrop(
        canvas: Canvas,
        bitmap: Bitmap,
        targetWidth: Int,
        targetHeight: Int,
    ) {
        val sourceRatio = bitmap.width.toFloat() / bitmap.height.toFloat()
        val targetRatio = targetWidth.toFloat() / targetHeight.toFloat()

        val src: Rect
        if (sourceRatio > targetRatio) {
            val cropWidth = (bitmap.height * targetRatio).toInt()
            val left = (bitmap.width - cropWidth) / 2
            src = Rect(left, 0, left + cropWidth, bitmap.height)
        } else {
            val cropHeight = (bitmap.width / targetRatio).toInt()
            val top = (bitmap.height - cropHeight) / 2
            src = Rect(0, top, bitmap.width, top + cropHeight)
        }

        val dst = RectF(0f, 0f, targetWidth.toFloat(), targetHeight.toFloat())
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        canvas.drawBitmap(bitmap, src, dst, paint)
    }

    private fun parseColor(value: String?): Int {
        if (value.isNullOrBlank()) {
            return Color.TRANSPARENT
        }

        val normalized = value.trim().removePrefix("#")
        val argb = when (normalized.length) {
            6 -> "FF$normalized"
            8 -> normalized
            else -> throw IllegalArgumentException(
                "Invalid adaptiveIconBackground color. Use #RRGGBB or #AARRGGBB."
            )
        }

        return try {
            Color.parseColor("#$argb")
        } catch (_: IllegalArgumentException) {
            throw IllegalArgumentException(
                "Invalid adaptiveIconBackground color: $value"
            )
        }
    }

    private fun createLaunchIntent(): Intent {
        val context = requireNotNull(appContext)
        val packageManager = context.packageManager

        packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            return it
        }

        val currentActivity = activity
            ?: throw IllegalStateException(
                "An attached Activity is required to create a pinned shortcut."
            )

        return Intent(context, currentActivity.javaClass)
    }

    private fun loadBitmap(imageType: String, imagePath: String): Bitmap? {
        return when (imageType) {
            "asset" -> {
                val assets = requireNotNull(flutterAssets) {
                    "Flutter assets are not available"
                }
                val lookupKey = assets.getAssetFilePathByName(imagePath)
                val assetManager = requireNotNull(appContext).assets
                decodeAndScale {
                    assetManager.open(lookupKey)
                }
            }

            "file" -> {
                val file = File(imagePath)
                if (!file.isFile || !file.canRead()) return null
                decodeAndScale { file.inputStream() }
            }

            else -> null
        }
    }

    private fun decodeAndScale(inputFactory: () -> InputStream): Bitmap? {
        val bounds = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }

        inputFactory().use { input ->
            BitmapFactory.decodeStream(input, null, bounds)
        }

        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            return null
        }

        val options = BitmapFactory.Options().apply {
            inSampleSize = calculateInSampleSize(
                bounds.outWidth,
                bounds.outHeight,
                MAX_ICON_DIMENSION
            )
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }

        val decoded = inputFactory().use { input ->
            BitmapFactory.decodeStream(input, null, options)
        } ?: return null

        val maxDimension = maxOf(decoded.width, decoded.height)
        if (maxDimension <= MAX_ICON_DIMENSION) {
            return decoded
        }

        val scale = MAX_ICON_DIMENSION.toFloat() / maxDimension.toFloat()
        val width = (decoded.width * scale).toInt().coerceAtLeast(1)
        val height = (decoded.height * scale).toInt().coerceAtLeast(1)
        val scaled = Bitmap.createScaledBitmap(decoded, width, height, true)
        if (scaled !== decoded) {
            decoded.recycle()
        }
        return scaled
    }

    private fun calculateInSampleSize(
        width: Int,
        height: Int,
        maxDimension: Int,
    ): Int {
        var sample = 1
        var current = maxOf(width, height)

        while (current / 2 >= maxDimension) {
            sample *= 2
            current /= 2
        }

        return sample
    }

    private fun handleShortcutIntent(intent: Intent?) {
        if (intent == null || intent === lastHandledIntent) return

        val id = intent.getStringExtra(EXTRA_SHORTCUT_ID) ?: return
        lastHandledIntent = intent

        val extraData = intent.getStringExtra(EXTRA_DATA)
        val event = mapOf<String, Any?>(
            "id" to id,
            "extraData" to extraData,
        )

        val sink = eventSink
        if (sink != null) {
            sink.success(event)
        } else {
            pendingShortcutEvent = event
        }
    }

    private fun detachFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
        activity = null
    }
}
