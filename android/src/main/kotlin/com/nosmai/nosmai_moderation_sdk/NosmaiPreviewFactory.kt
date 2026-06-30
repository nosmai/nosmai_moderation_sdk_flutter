package com.nosmai.nosmai_moderation_sdk

import android.content.Context
import android.view.View
import androidx.camera.view.PreviewView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Platform-view factory for the live camera preview, registered under the view
 * type "nosmai_moderation_sdk/preview" and embedded in Flutter via AndroidView.
 * The PreviewView is handed to [NosmaiLiveCamera] so detection and preview share
 * one CameraX session.
 */
class NosmaiPreviewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return NosmaiPreviewPlatformView(context)
    }
}

private class NosmaiPreviewPlatformView(context: Context) : PlatformView {
    private val previewView = PreviewView(context).apply {
        // PERFORMANCE (SurfaceView) — the camera preview gets a hardware overlay and
        // bypasses the GPU compositing path, so it no longer contends with the heavy
        // GPU detector (much less preview stutter). Flutter's SurfaceProducer
        // platform-view backend composites a SurfaceView correctly now.
        implementationMode = PreviewView.ImplementationMode.PERFORMANCE
        scaleType = PreviewView.ScaleType.FILL_CENTER
        NosmaiLiveCamera.attachPreview(this)
    }

    override fun getView(): View = previewView

    override fun dispose() {
        NosmaiLiveCamera.detachPreview(previewView)
    }
}
