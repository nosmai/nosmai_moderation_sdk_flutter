package com.nosmai.nosmai_moderation_sdk

import android.app.Activity
import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.camera.core.CameraSelector
import androidx.lifecycle.LifecycleOwner
import com.nosmai.detection.NosmaiListener
import com.nosmai.detection.NosmaiSDK
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import com.nosmai.detection.NosmaiCategory as SdkCategory
import com.nosmai.detection.NosmaiModel as SdkModel
import com.nosmai.detection.NosmaiNsfwClass as SdkNsfwClass
import com.nosmai.detection.NosmaiNsfwVerdict as SdkNsfwVerdict
import com.nosmai.detection.NosmaiResult as SdkResult
import com.nosmai.detection.NosmaiTextCategory as SdkTextCategory
import com.nosmai.detection.NosmaiTextLayer as SdkTextLayer
import com.nosmai.detection.NosmaiTextResult as SdkTextResult
import com.nosmai.detection.NosmaiVideoResult as SdkVideoResult

/**
 * Android side of the Nosmai moderation Flutter plugin. Implements the
 * Pigeon-generated [NosmaiModerationApi] (image / video / text — request/response)
 * and registers the native live-camera path (platform-view preview + start/stop
 * control channel + a per-frame result event stream), mirroring the iOS plugin.
 *
 * The blocking native calls (init + analyze) run on a background executor and
 * post their Pigeon callback on the main thread — never blocking the platform
 * thread.
 */
class NosmaiModerationSdkPlugin :
    FlutterPlugin,
    NosmaiModerationApi,
    ActivityAware,
    EventChannel.StreamHandler {

    private companion object {
        const val TAG = "NosmaiPlugin"
    }

    private var appContext: Context? = null
    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null
    private var control: MethodChannel? = null
    private var events: EventChannel? = null

    // Bounded worker pool for the blocking native calls. Recreated on each engine
    // attach because onDetachedFromEngine shuts it down and Flutter may reuse this
    // plugin instance across a detach -> re-attach (cached/grouped engines).
    private var bg = newPool()
    private val main = Handler(Looper.getMainLooper())

    private fun newPool() = Executors.newFixedThreadPool(2)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        if (bg.isShutdown) bg = newPool()
        NosmaiModerationApi.setUp(binding.binaryMessenger, this)

        binding.platformViewRegistry.registerViewFactory(
            "nosmai_moderation_sdk/preview", NosmaiPreviewFactory(),
        )

        control = MethodChannel(binding.binaryMessenger, "nosmai_moderation_sdk/live").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> { startLive(call.argument<String>("facing")); result.success(null) }
                    "stop" -> { NosmaiLiveCamera.stop(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
        }
        events = EventChannel(binding.binaryMessenger, "nosmai_moderation_sdk/live_events").apply {
            setStreamHandler(this@NosmaiModerationSdkPlugin)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Release the camera + native stream and stop the worker pool so the engine
        // (and any retained activity) can be torn down without leaking.
        NosmaiLiveCamera.stop()
        NosmaiModerationApi.setUp(binding.binaryMessenger, null)
        control?.setMethodCallHandler(null); control = null
        events?.setStreamHandler(null); events = null
        eventSink = null
        bg.shutdown()
        appContext = null
    }

    // ---- ActivityAware (CameraX needs the activity as a LifecycleOwner) ----

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onDetachedFromActivity() {
        // The bound LifecycleOwner is going away — stop the camera so the singleton
        // drops its reference to the dead activity (otherwise it leaks).
        NosmaiLiveCamera.stop()
        activity = null
    }

    // ---- EventChannel (live results) ----

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) { eventSink = sink }
    override fun onCancel(arguments: Any?) { eventSink = null }

    private fun startLive(facing: String?) {
        val act = activity
        if (act == null) {
            main.post { eventSink?.error("no_activity", "No host activity for the camera", null) }
            return
        }
        val owner = act as? LifecycleOwner
        if (owner == null) {
            main.post {
                eventSink?.error(
                    "no_lifecycle",
                    "Host activity is not a LifecycleOwner; the live camera needs a FlutterActivity/FragmentActivity host",
                    null,
                )
            }
            return
        }
        val lens = if (facing == "front") {
            CameraSelector.LENS_FACING_FRONT
        } else {
            CameraSelector.LENS_FACING_BACK
        }
        NosmaiLiveCamera.start(
            act, owner, lens,
            onResult = { r -> main.post { eventSink?.success(resultMap(r)) } },
            onError = { msg -> main.post { eventSink?.error("camera_error", msg, null) } },
        )
    }

    // ------------------------------------------------------------------
    // NosmaiModerationApi
    // ------------------------------------------------------------------

    override fun initialize(
        licenseKey: String,
        models: List<NosmaiModel>,
        callback: (Result<NosmaiInitResult>) -> Unit,
    ) {
        val ctx = appContext
        val sdkModels = models.map {
            when (it) {
                NosmaiModel.OBJECT_DETECTION -> SdkModel.OBJECT_DETECTION
                NosmaiModel.NSFW -> SdkModel.NSFW
                NosmaiModel.TEXT -> SdkModel.TEXT
            }
        }.toTypedArray()
        runOnBg(callback, { NosmaiInitResult(false, it) }) {
            val ok = ctx != null && NosmaiSDK.init(ctx, licenseKey, *sdkModels)
            NosmaiInitResult(ok, if (ok) null else "init/license failed")
        }
    }

    override fun initializeText(callback: (Result<Boolean>) -> Unit) {
        val ctx = appContext
        runOnBg(callback, { false }) {
            ctx != null && NosmaiSDK.initText(ctx)
        }
    }

    override fun analyzeImage(filePath: String, callback: (Result<NosmaiResult>) -> Unit) {
        runOnBg(callback, { safeResult() }) {
            val bmp = BitmapFactory.decodeFile(filePath) ?: return@runOnBg safeResult()
            try {
                toPigeon(NosmaiSDK.analyzeImage(bmp))
            } finally {
                bmp.recycle()  // we own the decoded bitmap; the SDK only snapshots it
            }
        }
    }

    override fun analyzeVideo(
        filePath: String,
        frameIntervalMs: Long,
        callback: (Result<NosmaiVideoResult>) -> Unit,
    ) {
        // analyzeVideo already runs decode + inference on its own worker and delivers
        // onComplete on the main thread, so call it directly. The try/catch only
        // guards the SYNCHRONOUS failure (e.g. not initialized -> checkInitialized
        // throws) so the Dart Future always completes instead of hanging/crashing.
        val ctx = appContext
        if (ctx == null) {
            main.post { callback(Result.success(emptyVideo())) }
            return
        }
        try {
            NosmaiSDK.analyzeVideo(ctx, Uri.fromFile(File(filePath)), frameIntervalMs, {}) { r ->
                main.post { callback(Result.success(toPigeon(r))) }
            }
        } catch (e: Throwable) {
            android.util.Log.e(TAG, "analyzeVideo failed: ${e.message}")
            main.post { callback(Result.success(emptyVideo())) }
        }
    }

    override fun moderateText(message: String, callback: (Result<NosmaiTextResult>) -> Unit) {
        // Fallback must be PURE (no native re-entry) — it may run on the main thread.
        runOnBg(callback, { emptyText() }) {
            toPigeon(NosmaiSDK.moderateText(message))
        }
    }

    override fun setThreshold(category: NosmaiCategory, value: Double) {
        try {
            NosmaiSDK.setThreshold(sdkCategory(category), value.toFloat())
        } catch (e: Throwable) {
            android.util.Log.e(TAG, "setThreshold failed: ${e.message}")
        }
    }

    override fun setNsfwThreshold(nsfwClass: NosmaiNsfwClass, value: Double) {
        try {
            NosmaiSDK.setNsfwThreshold(sdkNsfwClass(nsfwClass), value.toFloat())
        } catch (e: Throwable) {
            android.util.Log.e(TAG, "setNsfwThreshold failed: ${e.message}")
        }
    }

    override fun shutdown() {
        try {
            NosmaiLiveCamera.stop()
            NosmaiSDK.shutdown()
        } catch (e: Throwable) {
            android.util.Log.e(TAG, "shutdown failed: ${e.message}")
        }
    }

    // Runs [work] on the worker pool and ALWAYS delivers the Pigeon callback exactly
    // once on the main thread. Normally Result.success(work); if work throws,
    // Result.success(fallback(msg)). The boundary must never let an exception escape
    // (an uncaught throw would crash the platform/main thread or leave the Dart
    // Future pending forever). [fallback] should be pure, but even if it throws we
    // degrade to Result.failure so the Future still completes (with an error) rather
    // than hanging.
    private fun <T> runOnBg(
        callback: (Result<T>) -> Unit,
        fallback: (String) -> T,
        work: () -> T,
    ) {
        fun fail(msg: String): Result<T> = try {
            Result.success(fallback(msg))
        } catch (e: Throwable) {
            android.util.Log.e(TAG, "fallback failed: ${e.message}")
            Result.failure(e)
        }
        fun deliver(res: Result<T>) = main.post { callback(res) }

        val pool = bg
        if (pool.isShutdown) {
            deliver(fail("sdk detached"))
            return
        }
        try {
            pool.execute {
                val res = try {
                    Result.success(work())
                } catch (e: Throwable) {
                    android.util.Log.e(TAG, "moderation call failed: ${e.message}")
                    fail(e.message ?: "error")
                }
                deliver(res)
            }
        } catch (e: Throwable) {
            // RejectedExecutionException etc. — still complete the Future.
            deliver(fail(e.message ?: "rejected"))
        }
    }

    // ------------------------------------------------------------------
    // Mapping: native SDK types -> Pigeon types / event map
    // ------------------------------------------------------------------

    private fun toPigeon(r: SdkResult): NosmaiResult {
        val detections = r.detections.map {
            NosmaiObjectDetection(
                category = pigeonCategory(it.category),
                confidence = it.confidence.toDouble(),
            )
        }
        return NosmaiResult(
            isUnsafe = r.isUnsafe,
            detections = detections,
            nsfw = pigeonVerdict(r.nsfw),
            nsfwSafe = r.nsfwScores.safe.toDouble(),
            nsfwSexy = r.nsfwScores.sexy.toDouble(),
            nsfwExplicit = r.nsfwScores.explicit.toDouble(),
            rawWeapon = r.rawScores.weapon.toDouble(),
            rawDrug = r.rawScores.drug.toDouble(),
            rawCigarette = r.rawScores.cigarette.toDouble(),
            rawAlcohol = r.rawScores.alcohol.toDouble(),
        )
    }

    private fun toPigeon(r: SdkVideoResult): NosmaiVideoResult = NosmaiVideoResult(
        isUnsafe = r.isUnsafe,
        categories = r.categories.map { pigeonCategory(it) },
        flags = r.flags.map {
            NosmaiVideoFlag(
                timestampMs = it.timestampMs,
                category = pigeonCategory(it.category),
                confidence = it.confidence.toDouble(),
            )
        },
        framesAnalyzed = r.framesAnalyzed.toLong(),
        nsfw = pigeonVerdict(r.nsfw),
        nsfwFlaggedMs = r.nsfwFlaggedMs.map { it },
    )

    private fun toPigeon(r: SdkTextResult): NosmaiTextResult = NosmaiTextResult(
        blocked = r.blocked,
        layer = pigeonTextLayer(r.layer),
        category = pigeonTextCategory(r.category),
        score = r.score.toDouble(),
        matchedWord = r.matchedWord,
    )

    // Plain map for the live event stream (matches lib/src/live.dart).
    private fun resultMap(r: SdkResult): Map<String, Any?> = mapOf(
        "isUnsafe" to r.isUnsafe,
        "detections" to r.detections.map {
            mapOf("category" to pigeonCategory(it.category).raw, "confidence" to it.confidence.toDouble())
        },
        "nsfw" to pigeonVerdict(r.nsfw).raw,
        "nsfwSafe" to r.nsfwScores.safe.toDouble(),
        "nsfwSexy" to r.nsfwScores.sexy.toDouble(),
        "nsfwExplicit" to r.nsfwScores.explicit.toDouble(),
        "rawWeapon" to r.rawScores.weapon.toDouble(),
        "rawDrug" to r.rawScores.drug.toDouble(),
        "rawCigarette" to r.rawScores.cigarette.toDouble(),
        "rawAlcohol" to r.rawScores.alcohol.toDouble(),
    )

    // ---- Enum mapping by NAME (never by ordinal). Reordering either enum is then
    // a compile error here instead of a silent miscategorization. ----

    private fun sdkCategory(c: NosmaiCategory): SdkCategory = when (c) {
        NosmaiCategory.WEAPON -> SdkCategory.WEAPON
        NosmaiCategory.DRUG -> SdkCategory.DRUG
        NosmaiCategory.CIGARETTE -> SdkCategory.CIGARETTE
        NosmaiCategory.ALCOHOL -> SdkCategory.ALCOHOL
    }

    private fun pigeonCategory(c: SdkCategory): NosmaiCategory = when (c) {
        SdkCategory.WEAPON -> NosmaiCategory.WEAPON
        SdkCategory.DRUG -> NosmaiCategory.DRUG
        SdkCategory.CIGARETTE -> NosmaiCategory.CIGARETTE
        SdkCategory.ALCOHOL -> NosmaiCategory.ALCOHOL
    }

    private fun sdkNsfwClass(c: NosmaiNsfwClass): SdkNsfwClass = when (c) {
        NosmaiNsfwClass.EXPLICIT -> SdkNsfwClass.EXPLICIT
        NosmaiNsfwClass.SAFE -> SdkNsfwClass.SAFE
        NosmaiNsfwClass.SEXY -> SdkNsfwClass.SEXY
    }

    private fun pigeonVerdict(v: SdkNsfwVerdict): NosmaiNsfwVerdict = when (v) {
        SdkNsfwVerdict.SAFE -> NosmaiNsfwVerdict.SAFE
        SdkNsfwVerdict.WARN -> NosmaiNsfwVerdict.WARN
        SdkNsfwVerdict.BLOCK -> NosmaiNsfwVerdict.BLOCK
    }

    private fun pigeonTextLayer(l: SdkTextLayer): NosmaiTextLayer = when (l) {
        SdkTextLayer.NONE -> NosmaiTextLayer.NONE
        SdkTextLayer.BLOCKLIST -> NosmaiTextLayer.BLOCKLIST
        SdkTextLayer.CLASSIFIER -> NosmaiTextLayer.CLASSIFIER
    }

    private fun pigeonTextCategory(c: SdkTextCategory): NosmaiTextCategory = when (c) {
        SdkTextCategory.SAFE -> NosmaiTextCategory.SAFE
        SdkTextCategory.PROFANITY -> NosmaiTextCategory.PROFANITY
        SdkTextCategory.TOXIC -> NosmaiTextCategory.TOXIC
        SdkTextCategory.HATE -> NosmaiTextCategory.HATE
        SdkTextCategory.HARASSMENT -> NosmaiTextCategory.HARASSMENT
        SdkTextCategory.THREAT -> NosmaiTextCategory.THREAT
    }

    private fun safeResult() = NosmaiResult(
        isUnsafe = false,
        detections = emptyList(),
        nsfw = NosmaiNsfwVerdict.SAFE,
        nsfwSafe = 1.0,
        nsfwSexy = 0.0,
        nsfwExplicit = 0.0,
        rawWeapon = 0.0,
        rawDrug = 0.0,
        rawCigarette = 0.0,
        rawAlcohol = 0.0,
    )

    private fun emptyVideo() = NosmaiVideoResult(
        isUnsafe = false,
        categories = emptyList(),
        flags = emptyList(),
        framesAnalyzed = 0,
        nsfw = NosmaiNsfwVerdict.SAFE,
        nsfwFlaggedMs = emptyList(),
    )

    private fun emptyText() = NosmaiTextResult(
        blocked = false,
        layer = NosmaiTextLayer.NONE,
        category = NosmaiTextCategory.SAFE,
        score = 0.0,
        matchedWord = "",
    )
}
