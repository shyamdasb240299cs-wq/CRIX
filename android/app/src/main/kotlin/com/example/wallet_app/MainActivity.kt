package com.example.wallet_app

import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.wallet_app/overlay"
    private var overlayReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        overlayReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "com.example.wallet_app.OVERLAY_CLOSED") {
                    channel.invokeMethod("onOverlayClosed", null)
                } else if (intent?.action == "com.example.wallet_app.ADD_TX") {
                    val map = hashMapOf(
                        "name" to intent.getStringExtra("name"),
                        "amount" to intent.getDoubleExtra("amount", 0.0),
                        "isIncome" to intent.getBooleanExtra("isIncome", false),
                        "category" to (intent.getStringExtra("category") ?: "Others")
                    )
                    channel.invokeMethod("onOverlayAddTx", map)
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction("com.example.wallet_app.OVERLAY_CLOSED")
            addAction("com.example.wallet_app.ADD_TX")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(overlayReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(overlayReceiver, filter)
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> checkPermission(result)
                "requestPermission" -> requestPermission(result)
                "startOverlay" -> {
                    val intent = Intent(this, FloatingService::class.java).apply {
                        putExtra("expense", call.argument<String>("expense"))
                        putExtra("limit", call.argument<String>("limit"))
                        putExtra("left", call.argument<String>("left"))
                        putExtra("income", call.argument<String>("income"))
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "updateOverlay" -> {
                    val intent = Intent(this, FloatingService::class.java).apply {
                        putExtra("expense", call.argument<String>("expense"))
                        putExtra("limit", call.argument<String>("limit"))
                        putExtra("left", call.argument<String>("left"))
                        putExtra("income", call.argument<String>("income"))
                    }
                    startService(intent) // Will call onStartCommand again
                    result.success(true)
                }
                "stopOverlay" -> {
                    stopService(Intent(this, FloatingService::class.java))
                    result.success(true)
                }
                "isOverlayActive" -> {
                    result.success(FloatingService.isRunning)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        overlayReceiver?.let { unregisterReceiver(it) }
    }

    private fun checkPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            result.success(Settings.canDrawOverlays(this))
        } else {
            result.success(true)
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(this)) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:\$packageName")
                )
                startActivityForResult(intent, 1000)
                result.success(true)
            } else {
                result.success(true)
            }
        } else {
            result.success(true)
        }
    }
}
