package com.example.wallet_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class TransparentFlutterActivity : FlutterActivity() {
    private val CHANNEL = "com.example.wallet_app/overlay"

    override fun getBackgroundMode(): BackgroundMode {
        return BackgroundMode.transparent
    }

    override fun getInitialRoute(): String {
        return "/add_transaction"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "submitTransaction") {
                val intent = Intent("com.example.wallet_app.ADD_TX")
                intent.putExtra("name", call.argument<String>("name"))
                intent.putExtra("amount", call.argument<Double>("amount"))
                intent.putExtra("isIncome", call.argument<Boolean>("isIncome"))
                sendBroadcast(intent)
                
                result.success(true)
                finish() // Close the transparent activity
            } else {
                result.notImplemented()
            }
        }
    }
}
