package com.playball.app

import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

@RequiresApi(Build.VERSION_CODES.N)
class PlayBallTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        refresh()
    }

    override fun onClick() {
        super.onClick()
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch != null) startActivityAndCollapse(launch)
    }

    private fun refresh() {
        Thread {
            try {
                val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                val teamId = try {
                    prefs.getInt("flutter.widget_team_id", -1)
                } catch (e: ClassCastException) {
                    prefs.getLong("flutter.widget_team_id", -1L).toInt()
                }

                if (teamId <= 0) {
                    setTile("PlayBall", "마이팀 미설정")
                    return@Thread
                }

                val conn = URL("$BASE_URL/widget/my-team-scores/$teamId").openConnection() as HttpURLConnection
                conn.connectTimeout = 5000
                conn.readTimeout = 5000
                val text = conn.inputStream.bufferedReader().readText()
                conn.disconnect()

                val game = JSONObject(text).optJSONObject("game")
                if (game == null) {
                    setTile("오늘 경기 없음", "")
                    return@Thread
                }

                val homeTeam  = game.optString("home_team", "홈")
                val awayTeam  = game.optString("away_team", "원정")
                val homeScore = game.optInt("home_score", 0)
                val awayScore = game.optInt("away_score", 0)
                val status    = game.optString("status", "")
                val inning    = game.optInt("current_inning", 0)
                val half      = game.optString("inning_half", "")

                val label = "$homeTeam $homeScore : $awayScore $awayTeam"
                val sub = when (status) {
                    "진행" -> if (inning > 0) "${inning}회 $half" else "진행중"
                    "종료" -> "종료"
                    else   -> status
                }
                setTile(label, sub)

            } catch (_: Exception) {
                setTile("PlayBall", "")
            }
        }.start()
    }

    private fun setTile(label: String, subtitle: String) {
        val tile = qsTile ?: return
        tile.label = label
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = subtitle
        }
        tile.state = Tile.STATE_ACTIVE
        tile.updateTile()
    }
}
