package com.amian.plantdiseaseidentifier.services

// Reference copy: AppConfig/clients/Endpoints.kt. Change only the package when adopting in another app.

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/** Shared AppConfig endpoints format v1. Launch uses cached/default URLs; refresh never blocks launch. */
object Endpoints {
    private const val CACHE_KEY = "endpoints.v1"
    private val sources = listOf(
        "https://apptor-config.pages.dev/endpoints.json",
        "https://raw.githubusercontent.com/Amian/app-config/main/public/endpoints.json",
    )
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Any()
    private var appId = ""
    private var context: Context? = null
    private var defaults = emptyMap<String, String>()
    private var current = emptyMap<String, String>()
    private var refreshing = false
    private var lastRefresh = 0L

    fun configure(context: Context, appId: String, defaults: Map<String, String>) {
        val cached = try {
            val raw = context.getSharedPreferences(CACHE_KEY, Context.MODE_PRIVATE).getString(CACHE_KEY, null)
            raw?.let { parseServices(JSONObject(it)) } ?: emptyMap()
        } catch (_: Exception) { emptyMap() }
        synchronized(lock) {
            this.context = context.applicationContext
            this.appId = appId
            this.defaults = defaults
            current = defaults + cached
        }
        refresh(force = true)
    }

    fun url(name: String): String = synchronized(lock) {
        current[name] ?: defaults[name] ?: error("No endpoint for $name")
    }

    fun refresh(force: Boolean = false) {
        val id: String
        val app: Context
        synchronized(lock) {
            val now = System.currentTimeMillis()
            if (refreshing || (!force && now - lastRefresh < 60_000)) return
            app = context ?: return
            id = appId
            refreshing = true
            lastRefresh = now
        }
        scope.launch {
            try {
                for (source in sources) {
                    val services = fetch(source, id) ?: continue
                    synchronized(lock) { current = defaults + services }
                    app.getSharedPreferences(CACHE_KEY, Context.MODE_PRIVATE).edit()
                        .putString(CACHE_KEY, JSONObject(services).toString()).apply()
                    break
                }
            } finally { synchronized(lock) { refreshing = false } }
        }
    }

    private suspend fun fetch(source: String, id: String): Map<String, String>? = withContext(Dispatchers.IO) {
        var connection: HttpURLConnection? = null
        try {
            connection = URL(source).openConnection() as HttpURLConnection
            connection.connectTimeout = 5_000
            connection.readTimeout = 5_000
            if (connection.responseCode != 200) return@withContext null
            val file = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
            if (file.optInt("version", -1) != 1) return@withContext null
            val result = linkedMapOf<String, String>()
            for (section in listOf(file.opt("default"), file.optJSONObject("apps")?.opt(id))) {
                if (section == null) continue
                if (section !is JSONObject) return@withContext null
                result.putAll(parseServices(section) ?: return@withContext null)
            }
            result
        } catch (_: Exception) { null }
        finally { connection?.disconnect() }
    }

    private fun parseServices(section: JSONObject): Map<String, String>? {
        val result = linkedMapOf<String, String>()
        for (key in section.keys()) {
            val value = section.opt(key) as? String ?: return null
            val url = try { URL(value) } catch (_: Exception) { return null }
            if (url.protocol != "https" || url.host.isBlank()) return null
            result[key] = value
        }
        return result
    }
}
