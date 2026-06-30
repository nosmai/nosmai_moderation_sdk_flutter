package com.nosmai.nosmai_moderation_sdk

import android.content.Context
import android.util.Log
import android.util.Size
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.nosmai.detection.NosmaiListener
import com.nosmai.detection.NosmaiSDK
import java.util.concurrent.Executors
import com.nosmai.detection.NosmaiResult as SdkResult

/**
 * Owns the CameraX session for live moderation — the Android equivalent of the
 * iOS NosmaiCamera. Preview + frame analysis bind to the host activity lifecycle;
 * every frame goes to NosmaiSDK.pushFrame and only the per-frame result crosses
 * back to Dart. The preview platform view shares the same session.
 *
 * A process-wide singleton, so it MUST release every reference it holds to the
 * host activity/context on stop() — otherwise it leaks the Activity. start() is
 * idempotent (tears down any prior session first) so re-start / hot-restart /
 * activity recreation can never bind twice or to a dead lifecycle owner.
 */
object NosmaiLiveCamera {

    private const val TAG = "NosmaiLiveCamera"

    private val analysisExecutor = Executors.newSingleThreadExecutor()

    private var previewView: PreviewView? = null
    private var provider: ProcessCameraProvider? = null
    private var lifecycleOwner: LifecycleOwner? = null
    private var appContext: Context? = null
    private var onResult: ((SdkResult) -> Unit)? = null
    private var onError: ((String) -> Unit)? = null
    private var lensFacing = CameraSelector.LENS_FACING_BACK
    @Volatile private var running = false
    // Bumped on every start()/stop(); an in-flight async bind() whose token no
    // longer matches is stale and must not bind (cancels late provider callbacks).
    // Volatile: written on the platform thread (start/stop), read on the main
    // thread (the provider-future listener).
    @Volatile private var bindToken = 0

    /** Called by the platform view when its PreviewView is created. */
    fun attachPreview(view: PreviewView) {
        previewView = view
        if (running) bind()
    }

    /** Called by the platform view on dispose. Clears only if this exact view is
     *  still current — a newer view may have attached during a screen transition. */
    fun detachPreview(view: PreviewView) {
        if (previewView === view) previewView = null
    }

    @Synchronized
    fun start(
        context: Context,
        owner: LifecycleOwner,
        lensFacing: Int,
        onResult: (SdkResult) -> Unit,
        onError: (String) -> Unit,
    ) {
        // Idempotent: drop any prior session (and its activity refs) first.
        stop()
        appContext = context.applicationContext
        lifecycleOwner = owner
        this.lensFacing = lensFacing
        this.onResult = onResult
        this.onError = onError
        running = true
        bindToken++
        NosmaiSDK.startStream(object : NosmaiListener {
            override fun onResult(result: SdkResult) {
                this@NosmaiLiveCamera.onResult?.invoke(result)
            }
        })
        bind()
    }

    @Synchronized
    fun stop() {
        running = false
        bindToken++  // cancel any in-flight bind()
        NosmaiSDK.stopStream()
        try {
            provider?.unbindAll()
        } catch (e: Throwable) {
            Log.e(TAG, "unbindAll failed: ${e.message}")
        }
        provider = null
        // Release every reference to the host so the Activity can be GC'd. The
        // previewView is owned by the platform view (cleared via detachPreview).
        lifecycleOwner = null
        appContext = null
        onResult = null
        onError = null
    }

    // Binds preview + analysis once both the camera provider and the preview view
    // are available (the platform view and start() can arrive in either order).
    private fun bind() {
        val ctx = appContext ?: return
        val owner = lifecycleOwner ?: return
        val view = previewView ?: return
        val token = bindToken

        val future = ProcessCameraProvider.getInstance(ctx)
        future.addListener({
            val cameraProvider = try {
                future.get()
            } catch (e: Throwable) {
                Log.e(TAG, "camera provider init failed: ${e.message}")
                return@addListener
            }
            // Synchronize with start()/stop() so a stop() can't slip in between the
            // staleness check and bindToLifecycle (which would rebind after stop).
            synchronized(this) {
                if (!running || token != bindToken) return@addListener
                provider = cameraProvider

                val preview = Preview.Builder().build().also {
                    it.surfaceProvider = view.surfaceProvider
                }
                val analysis = ImageAnalysis.Builder()
                    .setResolutionSelector(
                        ResolutionSelector.Builder()
                            .setResolutionStrategy(
                                ResolutionStrategy(
                                    Size(1280, 720),
                                    ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,
                                ),
                            )
                            .build(),
                    )
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageRotationEnabled(true)
                    .build()
                analysis.setAnalyzer(analysisExecutor) { proxy: ImageProxy ->
                    // pushFrame snapshots the frame and always closes the proxy.
                    NosmaiSDK.pushFrame(proxy)
                }

                // Try the requested lens; if that camera isn't present (e.g. a
                // front-only tablet asked for back), fall back to the other lens.
                // If neither binds, report the error to Dart instead of crashing.
                val primary = lensFacing
                val fallback = if (primary == CameraSelector.LENS_FACING_BACK)
                    CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK
                cameraProvider.unbindAll()
                if (!tryBind(cameraProvider, owner, primary, preview, analysis) &&
                    !tryBind(cameraProvider, owner, fallback, preview, analysis)
                ) {
                    Log.e(TAG, "camera bind failed for both lenses")
                    onError?.invoke("Camera could not be started (no usable camera)")
                }
            }
        }, ContextCompat.getMainExecutor(ctx))
    }

    private fun tryBind(
        provider: ProcessCameraProvider,
        owner: LifecycleOwner,
        lens: Int,
        preview: Preview,
        analysis: ImageAnalysis,
    ): Boolean = try {
        val selector = CameraSelector.Builder().requireLensFacing(lens).build()
        if (!provider.hasCamera(selector)) {
            false
        } else {
            provider.bindToLifecycle(owner, selector, preview, analysis)
            true
        }
    } catch (e: Throwable) {
        Log.e(TAG, "camera bind failed (lens=$lens): ${e.message}")
        false
    }
}
