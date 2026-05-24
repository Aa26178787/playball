package com.playball.app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

const val ACTION_UPDATE = "com.playball.app.UPDATE_WIDGET"
const val PREFS_NAME = "FlutterSharedPreferences"
const val KEY_TEAM_ID = "flutter.widget_team_id"
const val BASE_URL = "http://168.107.61.147:8000"
const val NOTIF_CHANNEL_ID = "playball_live"
const val NOTIF_ID = 7788

class PlayBallWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        performUpdate(context)
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: android.os.Bundle) {
        performUpdate(context)
    }

    override fun onEnabled(context: Context) {
        scheduleAlarm(context)
        performUpdate(context)
    }

    override fun onDisabled(context: Context) {
        cancelAlarm(context)
        cancelNotification(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_UPDATE) {
            performUpdate(context)
        }
    }

    companion object {

        fun scheduleAlarm(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pi = getAlarmPendingIntent(context)
            val interval = 5 * 60 * 1000L
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC, System.currentTimeMillis() + interval, pi)
            } else {
                am.setRepeating(AlarmManager.RTC, System.currentTimeMillis() + interval, interval, pi)
            }
        }

        fun cancelAlarm(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(getAlarmPendingIntent(context))
        }

        private fun getAlarmPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, PlayBallWidget::class.java).apply {
                action = ACTION_UPDATE
            }
            return PendingIntent.getBroadcast(
                context, 100, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        fun cancelNotification(context: Context) {
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIF_ID)
        }

        fun performUpdate(context: Context) {
            Thread {
                try {
                    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    val teamId = try {
                        prefs.getInt("flutter.widget_team_id", -1)
                    } catch (e: ClassCastException) {
                        prefs.getLong("flutter.widget_team_id", -1L).toInt()
                    }

                    val data: JSONObject? = if (teamId > 0) fetchData(teamId) else null

                    updateAllWidgets(context, teamId, data)
                    updateNotification(context, teamId, data)

                    // 5분 후 다음 알람 재예약 (exact alarm 방식)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        scheduleAlarm(context)
                    }

                    // 타일 갱신 요청
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        PlayBallTileService.requestListeningState(
                            context, ComponentName(context, PlayBallTileService::class.java)
                        )
                    }
                } catch (_: Exception) {}
            }.start()
        }

        private fun fetchData(teamId: Int): JSONObject? = try {
            val conn = URL("$BASE_URL/widget/my-team-scores/$teamId").openConnection() as HttpURLConnection
            conn.connectTimeout = 6000
            conn.readTimeout = 6000
            val text = conn.inputStream.bufferedReader().readText()
            conn.disconnect()
            JSONObject(text)
        } catch (_: Exception) { null }

        private fun updateAllWidgets(context: Context, teamId: Int, data: JSONObject?) {
            val awm = AppWidgetManager.getInstance(context)
            val ids = awm.getAppWidgetIds(ComponentName(context, PlayBallWidget::class.java))
            for (id in ids) {
                val opts = awm.getAppWidgetOptions(id)
                val h = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 40)
                val views = buildViews(context, teamId, data, h)
                awm.updateAppWidget(id, views)
            }
        }

        private fun buildViews(context: Context, teamId: Int, data: JSONObject?, heightDp: Int): RemoteViews {
            val layoutId = when {
                heightDp >= 130 -> R.layout.widget_large
                heightDp >= 80  -> R.layout.widget_medium
                else            -> R.layout.widget_small
            }
            val v = RemoteViews(context.packageName, layoutId)

            // 앱 실행 인텐트
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                val pi = PendingIntent.getActivity(
                    context, 0, launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                v.setOnClickPendingIntent(R.id.widget_root, pi)
            }

            if (teamId <= 0) {
                v.setTextViewText(R.id.widget_home_team, "PlayBall")
                v.setTextViewText(R.id.widget_away_team, "")
                v.setTextViewText(R.id.widget_score, "마이팀 설정 필요")
                v.setTextViewText(R.id.widget_status, "앱에서 마이팀을 설정하세요")
                return v
            }

            val game = data?.optJSONObject("game")
            if (game == null) {
                v.setTextViewText(R.id.widget_home_team, "오늘")
                v.setTextViewText(R.id.widget_away_team, "")
                v.setTextViewText(R.id.widget_score, "경기 없음")
                v.setTextViewText(R.id.widget_status, "")
                return v
            }

            val homeTeam  = game.optString("home_team", "홈")
            val awayTeam  = game.optString("away_team", "원정")
            val homeScore = game.optInt("home_score", 0)
            val awayScore = game.optInt("away_score", 0)
            val status    = game.optString("status", "예정")
            val inning    = game.optInt("current_inning", 0)
            val half      = game.optString("inning_half", "")
            val startTime = game.optString("start_time", "").take(5)

            val statusText = when (status) {
                "진행" -> if (inning > 0) "${inning}회 $half" else "진행중"
                "종료" -> "종료"
                "취소" -> "취소"
                else   -> startTime
            }

            v.setTextViewText(R.id.widget_home_team, homeTeam)
            v.setTextViewText(R.id.widget_away_team, awayTeam)
            v.setTextViewText(R.id.widget_score, "$homeScore : $awayScore")
            v.setTextViewText(R.id.widget_status, statusText)
            return v
        }

        fun updateNotification(context: Context, teamId: Int, data: JSONObject?) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val ch = NotificationChannel(NOTIF_CHANNEL_ID, "실시간 경기 스코어", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "마이팀 실시간 경기 스코어"
                    setShowBadge(false)
                }
                nm.createNotificationChannel(ch)
            }

            val game = data?.optJSONObject("game")
            if (teamId <= 0 || game == null || game.optString("status") != "진행") {
                nm.cancel(NOTIF_ID)
                return
            }

            val homeTeam  = game.optString("home_team", "홈")
            val awayTeam  = game.optString("away_team", "원정")
            val homeScore = game.optInt("home_score", 0)
            val awayScore = game.optInt("away_score", 0)
            val inning    = game.optInt("current_inning", 0)
            val half      = game.optString("inning_half", "")

            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val pi = PendingIntent.getActivity(
                context, 1, launch!!,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notif = NotificationCompat.Builder(context, NOTIF_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_widget_notif)
                .setContentTitle("$homeTeam  $homeScore : $awayScore  $awayTeam")
                .setContentText(if (inning > 0) "${inning}회 $half" else "진행중")
                .setOngoing(true)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setContentIntent(pi)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()

            nm.notify(NOTIF_ID, notif)
        }
    }
}
