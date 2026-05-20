package com.example.wallet_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class FloatingService : Service() {

    companion object {
        var isRunning = false
    }

    private val CHANNEL_ID = "OverlayForegroundServiceChannel"
    private var floatingView: FloatingView? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()
        startForeground(1, createNotification())
        
        floatingView = FloatingView(this) {
            stopSelf()
        }
        floatingView?.show()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val expense = intent?.getStringExtra("expense") ?: "₹0"
        val limit = intent?.getStringExtra("limit") ?: "₹0"
        val left = intent?.getStringExtra("left") ?: "₹0"
        val income = intent?.getStringExtra("income") ?: "₹0"
        
        floatingView?.updateData(expense, limit, left, income)
        
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        floatingView?.remove()

        val intent = Intent("com.example.wallet_app.OVERLAY_CLOSED")
        intent.setPackage(packageName)
        sendBroadcast(intent)
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Overlay Service Channel",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }

    private fun createNotification(): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            pendingIntentFlags
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("CRIX Wallet Widget Active")
            .setContentText("The floating overlay is running.")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .build()
    }
}
