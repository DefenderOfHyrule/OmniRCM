package io.github.omnircm.rcm

import io.github.omnircm.OmniRcmApp
import io.github.omnircm.data.Payload
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipInputStream

data class RemotePayloadSpec(
    val name: String,
    val repo: String,
    val assetFilter: (String) -> Boolean,
    val postProcess: ((File) -> File)? = null,
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

    val specs = listOf(
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

    fun getCachedPayloads(): List<Payload> {
        val result = mutableListOf<Payload>()
        for (spec in specs) {
            val versionFile = File(cacheDir, "${spec.name}.version")
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

    fun fetchAll(onLog: (String) -> Unit) {
        for (spec in specs) {
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

        val versionFile = File(cacheDir, "${spec.name}.version")
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
        val tmpFile = File(cacheDir, assetName!!)
        downloadFile(dlUrl, tmpFile, onLog)

        val finalFile = if (spec.postProcess != null) {
            onLog("  Extracting ${spec.name}...")
            val result = spec.postProcess.invoke(tmpFile)
            tmpFile.delete()
            result
        } else {
            tmpFile
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

    private fun resolveLocalFile(spec: RemotePayloadSpec): File? {
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
