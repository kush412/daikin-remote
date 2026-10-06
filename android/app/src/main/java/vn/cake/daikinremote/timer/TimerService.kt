package vn.cake.daikinremote.timer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import vn.cake.daikinremote.R
import vn.cake.daikinremote.data.RemoteRepository
import java.text.DateFormat
import java.util.Date

/**
 * Keeps the process alive while a phone-run timer is pending, with an ongoing notification
 * showing when it will fire. Stops itself once no timer is left.
 */
class TimerService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel(this)
        startInForeground(buildNotification("Timer set"))
        scope.launch {
            val repo = RemoteRepository.get(this@TimerService)
            repo.current()
            repo.stored.collectLatest { stored ->
                val s = stored?.state ?: return@collectLatest
                if (s.onTimerAt == null && s.offTimerAt == null) {
                    stopSelf()
                    return@collectLatest
                }
                val text = listOfNotNull(
                    s.onTimerAt?.let { "On at ${clock(it)}" },
                    s.offTimerAt?.let { "Off at ${clock(it)}" },
                ).joinToString("  ·  ")
                getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification(text))
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun startInForeground(n: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
    }

    private fun buildNotification(text: String): Notification =
        Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle("AC timer")
            .setContentText("$text — keep the phone pointed at the AC")
            .setContentIntent(TimerScheduler.showPendingIntent(this))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()

    companion object {
        private const val CHANNEL_ID = "timer"
        private const val NOTIFICATION_ID = 1

        fun start(context: Context) {
            try {
                context.startForegroundService(Intent(context, TimerService::class.java))
            } catch (e: Exception) {
                // Background start not allowed (e.g. Android 12+ restrictions); the alarm still fires.
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, TimerService::class.java))
        }

        private fun createChannel(context: Context) {
            val nm = context.getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "AC timer", NotificationManager.IMPORTANCE_LOW),
            )
        }

        private fun clock(ms: Long) = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(ms))
    }
}
