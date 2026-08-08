package io.github.omnircm.rcm

import android.content.Context
import io.github.omnircm.OmniRcmApp
import io.github.omnircm.data.CustomPayloadSource
import io.github.omnircm.data.Payload
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipInputStream

data class RemotePayloadSpec(
    val name: String,
    val repo: String,
    val assetFilter: (String) -> Boolean,
    val postProcess: ((File) -> File)? = null,
    val cacheKey: String = name,
    val isCustomSource: Boolean = false,
)

object PayloadFetcher {

    private val cacheDir: File
        get() = File(
            OmniRcmApp.instance.getExternalFilesDir(null) ?: OmniRcmApp.instance.filesDir,
            "payloads"
        ).also { it.mkdirs() }

    private val http = OkHttpClient.Builder()
        .addInterceptor { chain ->
            chain.proceed(
                chain.request().newBuilder()
                    .header("User-Agent", "OmniRCM/payload-fetcher")
                    .build()
            )
        }
        .build()

    val builtinSpecs = listOf(
        RemotePayloadSpec(
            name = "fusee",
            repo = "Atmosphere-NX/Atmosphere",
            assetFilter = { it == "fusee.bin" },
        ),
        RemotePayloadSpec(
            name = "hekate",
            repo = "CTCaer/hekate",
            assetFilter = { it.startsWith("hekate_ctcaer") && it.endsWith(".zip") },
            postProcess = ::extractHekate,
        ),
        RemotePayloadSpec(
            name = "TegraExplorer",
            repo = "suchmememanyskill/TegraExplorer",
            assetFilter = { it == "TegraExplorer.bin" },
        ),
    )

    private val reservedSourceNames = setOf("fusee", "hekate", "tegraexplorer", "custom")

    private fun prefs() =
        OmniRcmApp.instance.getSharedPreferences("omnircm_prefs", Context.MODE_PRIVATE)

    fun getCustomSources(): List<CustomPayloadSource> {
        val raw = prefs().getString("custom_sources", null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                CustomPayloadSource(
                    name = o.getString("name"),
                    repo = o.getString("repo"),
                    assetMatch = o.getString("assetMatch"),
                    isZip = o.optBoolean("isZip", false),
                    zipInnerPattern = o.optString("zipInnerPattern", "*.bin"),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    fun setCustomSources(sources: List<CustomPayloadSource>) {
        val arr = JSONArray()
        for (s in sources) {
            val o = JSONObject()
            o.put("name", s.name)
            o.put("repo", s.repo)
            o.put("assetMatch", s.assetMatch)
            o.put("isZip", s.isZip)
            o.put("zipInnerPattern", s.zipInnerPattern)
            arr.put(o)
        }
        prefs().edit().putString("custom_sources", arr.toString()).apply()
    }

    fun addCustomSource(source: CustomPayloadSource): String? {
        val name = source.name.trim()
        val repo = source.repo.trim()
        val assetMatch = source.assetMatch.trim()

        if (name.isEmpty() || repo.isEmpty() || assetMatch.isEmpty()) return "All fields are required."
        if (!repo.contains('/')) return "Repository must be in the form owner/repo."
        if (reservedSourceNames.contains(name.lowercase())) return "That name is reserved, please choose another."

        val existing = getCustomSources()
        if (existing.any { it.name.equals(name, ignoreCase = true) }) return "A source with that name already exists."

        val cleaned = source.copy(
            name = name,
            repo = repo,
            assetMatch = assetMatch,
            zipInnerPattern = source.zipInnerPattern.trim().ifEmpty { "*.bin" },
        )
        setCustomSources(existing + cleaned)
        return null
    }

    fun removeCustomSource(name: String) {
        val existing = getCustomSources()
        val target = existing.firstOrNull { it.name == name }
        setCustomSources(existing.filterNot { it.name == name })
        if (target != null) {
            val cacheKey = "custom_" + sanitizeKey(target.name)
            cacheDir.listFiles()?.forEach { f ->
                val matches = f.name == "$cacheKey.version" ||
                    f.name == "$cacheKey.localpath" ||
                    f.name.startsWith("${cacheKey}__") ||
                    f.name == "__${cacheKey}_tmp__"
                if (matches) {
                    if (f.isDirectory) f.deleteRecursively() else f.delete()
                }
            }
        }
    }

    private fun sanitizeKey(name: String): String {
        val key = name.filter { it.isLetterOrDigit() }.lowercase()
        return key.ifEmpty { java.util.UUID.randomUUID().toString().take(8) }
    }

    private fun matchesAssetPattern(fileName: String, pattern: String): Boolean {
        return if (pattern.contains('*') || pattern.contains('?')) {
            wildcardToRegex(pattern).matches(fileName)
        } else {
            fileName.contains(pattern, ignoreCase = true)
        }
    }

    private fun wildcardToRegex(pattern: String): Regex {
        val sb = StringBuilder("^")
        for (c in pattern) {
            when (c) {
                '*' -> sb.append(".*")
                '?' -> sb.append('.')
                else -> sb.append(Regex.escape(c.toString()))
            }
        }
        sb.append("$")
        return Regex(sb.toString(), RegexOption.IGNORE_CASE)
    }

    private fun buildCustomSpec(source: CustomPayloadSource): RemotePayloadSpec {
        val cacheKey = "custom_" + sanitizeKey(source.name)
        return RemotePayloadSpec(
            name = source.name,
            cacheKey = cacheKey,
            repo = source.repo,
            assetFilter = { matchesAssetPattern(it, source.assetMatch) },
            postProcess = if (source.isZip) {
                { zipFile -> extractCustomZip(cacheKey, zipFile, source.zipInnerPattern) }
            } else null,
            isCustomSource = true,
        )
    }

    private fun allSpecs(): List<RemotePayloadSpec> =
        builtinSpecs + getCustomSources().map(::buildCustomSpec)

    fun getCachedPayloads(): List<Payload> {
        val result = mutableListOf<Payload>()
        for (spec in allSpecs()) {
            val versionFile = File(cacheDir, "${spec.cacheKey}.version")
            val version = if (versionFile.exists()) versionFile.readText().trim() else null
            val file = resolveLocalFile(spec) ?: continue
            result.add(Payload(spec.name, file, isRemote = true, version = version))
        }
        return result
    }

    fun getCustomPayloads(): List<Payload> {
        val dir = customDir()
        if (!dir.exists()) return emptyList()
        return dir.listFiles()
            ?.filter { it.extension == "bin" }
            ?.map { Payload(it.nameWithoutExtension, it, isCustom = true) }
            ?: emptyList()
    }

    private fun sanitizeBaseName(raw: String): String {
        val cleaned = raw.trim()
            .replace(Regex("[\\\\/:*?\"<>|]"), "_")
            .trim(' ', '.')
        return cleaned.ifBlank { "payload" }
    }

    private fun baseNameFrom(displayName: String): String {
        val lastSegment = displayName.substringAfterLast('/').substringAfterLast('\\')
        val withoutExt = if (lastSegment.contains('.')) lastSegment.substringBeforeLast('.') else lastSegment
        return sanitizeBaseName(withoutExt)
    }

    private fun uniqueCustomFile(baseName: String): File {
        val dir = customDir()
        var candidate = File(dir, "$baseName.bin")
        var counter = 1
        while (candidate.exists()) {
            candidate = File(dir, "$baseName ($counter).bin")
            counter++
        }
        return candidate
    }

    fun importCustomPayload(displayName: String, input: java.io.InputStream): File {
        val dest = uniqueCustomFile(baseNameFrom(displayName))
        FileOutputStream(dest).use { out -> input.copyTo(out) }
        return dest
    }

    fun renameCustomPayload(payload: Payload, newName: String): File? {
        if (!payload.isCustom) return null
        val newBase = baseNameFrom(newName)
        if (newBase == payload.file.nameWithoutExtension) return payload.file
        val dest = uniqueCustomFile(newBase)
        return if (payload.file.renameTo(dest)) dest else null
    }

    fun fetchAll(onLog: (String) -> Unit) {
        for (spec in allSpecs()) {
            try {
                onLog("Checking ${spec.name}...")
                fetchOne(spec, onLog)
            } catch (e: Exception) {
                onLog("[WARN] ${spec.name}: ${e.message}")
            }
        }
    }

    private fun fetchOne(spec: RemotePayloadSpec, onLog: (String) -> Unit) {
        val json = httpGet("https://api.github.com/repos/${spec.repo}/releases/latest")
        val root = JSONObject(json)
        val tag = root.getString("tag_name")
        val version = tag.trimStart('v', 'V')

        val versionFile = File(cacheDir, "${spec.cacheKey}.version")
        val cachedVersion = if (versionFile.exists()) versionFile.readText().trim() else null
        val cachedFile = resolveLocalFile(spec)

        if (cachedVersion == version && cachedFile != null) {
            onLog("  ${spec.name} already up to date ($tag).")
            return
        }

        val assets = root.getJSONArray("assets")
        var dlUrl: String? = null
        var assetName: String? = null

        for (i in 0 until assets.length()) {
            val asset = assets.getJSONObject(i)
            val name = asset.getString("name")
            val url = asset.getString("browser_download_url")
            if (spec.assetFilter(name)) {
                dlUrl = url
                assetName = name
                break
            }
        }

        if (dlUrl == null) return

        onLog("  Downloading ${spec.name} $tag...")
        val tmpFile = File(cacheDir, if (spec.isCustomSource) "${spec.cacheKey}__$assetName" else assetName!!)
        downloadFile(dlUrl, tmpFile, onLog)

        val finalFile = if (spec.postProcess != null) {
            onLog("  Extracting ${spec.name}...")
            val result = spec.postProcess.invoke(tmpFile)
            tmpFile.delete()
            result
        } else {
            tmpFile
        }

        if (spec.isCustomSource) {
            File(cacheDir, "${spec.cacheKey}.localpath").writeText(finalFile.absolutePath)
        }

        versionFile.writeText(version)
        onLog("  ${spec.name} $tag ready.")
    }

    private fun downloadFile(url: String, dest: File, onLog: (String) -> Unit) {
        val req = Request.Builder().url(url).build()
        http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw Exception("HTTP ${resp.code}")
            val body = resp.body ?: throw Exception("Empty response")
            val total = body.contentLength()
            var received = 0L
            var lastPct = -1
            body.byteStream().use { src ->
                FileOutputStream(dest).use { dst ->
                    val buf = ByteArray(81920)
                    var read: Int
                    while (src.read(buf).also { read = it } != -1) {
                        dst.write(buf, 0, read)
                        received += read
                        if (total > 0) {
                            val pct = (received * 100 / total).toInt()
                            if (pct / 10 != lastPct / 10) {
                                onLog("    $pct%")
                                lastPct = pct
                            }
                        }
                    }
                }
            }
        }
    }

    private fun httpGet(url: String): String {
        val req = Request.Builder().url(url).build()
        return http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw Exception("HTTP ${resp.code}")
            resp.body?.string() ?: throw Exception("Empty response")
        }
    }

    private fun extractHekate(zipFile: File): File {
        val tmpDir = File(cacheDir, "__hekate_tmp__")
        if (tmpDir.exists()) tmpDir.deleteRecursively()
        tmpDir.mkdirs()

        ZipInputStream(zipFile.inputStream()).use { zip ->
            var entry = zip.nextEntry
            while (entry != null) {
                if (!entry.isDirectory) {
                    val outFile = File(tmpDir, File(entry.name).name)
                    FileOutputStream(outFile).use { zip.copyTo(it) }
                }
                entry = zip.nextEntry
            }
        }

        val bin = tmpDir.listFiles()?.firstOrNull {
            it.name.startsWith("hekate_ctcaer") && it.extension == "bin"
        } ?: throw Exception("hekate_ctcaer*.bin not found in zip")

        for (old in cacheDir.listFiles() ?: emptyArray()) {
            if (old.name.startsWith("hekate_ctcaer") && old.extension == "bin")
                old.delete()
        }

        val dest = File(cacheDir, bin.name)
        bin.copyTo(dest, overwrite = true)
        tmpDir.deleteRecursively()
        return dest
    }

    private fun extractCustomZip(cacheKey: String, zipFile: File, innerPattern: String): File {
        val tmpDir = File(cacheDir, "__${cacheKey}_tmp__")
        if (tmpDir.exists()) tmpDir.deleteRecursively()
        tmpDir.mkdirs()

        ZipInputStream(zipFile.inputStream()).use { zip ->
            var entry = zip.nextEntry
            while (entry != null) {
                if (!entry.isDirectory) {
                    val outFile = File(tmpDir, File(entry.name).name)
                    FileOutputStream(outFile).use { zip.copyTo(it) }
                }
                entry = zip.nextEntry
            }
        }

        val pattern = innerPattern.ifBlank { "*.bin" }
        val regex = wildcardToRegex(pattern)
        val match = tmpDir.listFiles()?.firstOrNull { regex.matches(it.name) }
            ?: throw Exception("No file matching \"$pattern\" found in the downloaded archive.")

        val dest = File(cacheDir, "${cacheKey}__${match.name}")
        match.copyTo(dest, overwrite = true)
        tmpDir.deleteRecursively()
        return dest
    }

    private fun resolveLocalFile(spec: RemotePayloadSpec): File? {
        if (spec.isCustomSource) {
            val marker = File(cacheDir, "${spec.cacheKey}.localpath")
            if (!marker.exists()) return null
            return File(marker.readText().trim()).takeIf { it.exists() }
        }
        return if (spec.name == "hekate") {
            cacheDir.listFiles()?.firstOrNull {
                it.name.startsWith("hekate_ctcaer") && it.extension == "bin"
            }
        } else {
            val name = when (spec.name) {
                "fusee" -> "fusee.bin"
                "TegraExplorer" -> "TegraExplorer.bin"
                else -> "${spec.name}.bin"
            }
            File(cacheDir, name).takeIf { it.exists() }
        }
    }

    fun customDir(): File = File(
        OmniRcmApp.instance.getExternalFilesDir(null) ?: OmniRcmApp.instance.filesDir,
        "custom"
    ).also { it.mkdirs() }
}
