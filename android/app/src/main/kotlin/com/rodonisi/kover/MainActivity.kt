package com.rodonisi.kover

import android.view.KeyEvent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var volumeKeySink: EventChannel.EventSink? = null
    private val capturedKeyCodes = mutableSetOf<Int>()

    private val volumeKeyChannel = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            volumeKeySink = events
        }

        override fun onCancel(arguments: Any?) {
            volumeKeySink = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        EventChannel(messenger, "kover/volume_keys").setStreamHandler(volumeKeyChannel)
        MethodChannel(messenger, "kover/volume_key_capture").setMethodCallHandler { call, result ->
            when (call.method) {
                "setCapturedKeys" -> {
                    capturedKeyCodes.clear()
                    (call.arguments as? List<*>)?.filterIsInstance<Int>()
                        ?.let(capturedKeyCodes::addAll)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode in capturedKeyCodes && volumeKeySink != null) {
            volumeKeySink?.success(keyCode)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }
}
