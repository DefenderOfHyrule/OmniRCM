package io.github.omnircm

import android.app.Application
import android.content.Context
import androidx.appcompat.app.AppCompatDelegate

class OmniRcmApp : Application() {
    override fun onCreate() {
        super.onCreate()
        instance = this
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isDark = prefs.getBoolean(KEY_DARK_MODE, true)
        AppCompatDelegate.setDefaultNightMode(
            if (isDark) AppCompatDelegate.MODE_NIGHT_YES
            else        AppCompatDelegate.MODE_NIGHT_NO
        )
    }

    companion object {
        lateinit var instance: OmniRcmApp
            private set

        const val PREFS_NAME    = "omnircm_ui_prefs"
        const val KEY_DARK_MODE = "dark_mode"
    }
}
