package io.github.omnircm.ui

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.View
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatDelegate
import androidx.lifecycle.lifecycleScope
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.materialswitch.MaterialSwitch
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import io.github.omnircm.OmniRcmApp
import io.github.omnircm.R
import io.github.omnircm.data.Payload
import io.github.omnircm.rcm.UpdateChecker
import io.github.omnircm.rcm.UpdateInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream

class MainActivity : AppCompatActivity() {

    private lateinit var vm: MainViewModel
    private lateinit var adapter: PayloadAdapter

    private lateinit var pillStatus: TextView
    private lateinit var pillDot: View
    private lateinit var injectButton: Button
    private lateinit var logView: TextView
    private lateinit var autoInjectSwitch: MaterialSwitch
    private var pendingSelectName: String? = null
    private lateinit var selectedPayloadCard: LinearLayout
    private lateinit var selectedPayloadName: android.widget.TextView
    private lateinit var selectedPayloadSize: android.widget.TextView

    private lateinit var btnThemeToggle: ImageButton
    private lateinit var btnLogToggle: LinearLayout
    private lateinit var logSection: LinearLayout
    private lateinit var resultPanel: LinearLayout
    private lateinit var resultPanelTitle: TextView
    private lateinit var resultPanelDetail: TextView
    private lateinit var btnResultDismiss: Button

    private var logVisible = false

    private val pollHandler = Handler(Looper.getMainLooper())
    private val pollRunnable = object : Runnable {
        override fun run() {
            vm.pollDevice()
            pollHandler.postDelayed(this, 1500)
        }
    }

    private val pickFileLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            result.data?.data?.let { importPayload(it) }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        vm = androidx.lifecycle.ViewModelProvider(this)[MainViewModel::class.java]
        setContentView(R.layout.activity_main)

        pillStatus        = findViewById(R.id.pill_status)
        pillDot           = findViewById(R.id.pill_dot)
        injectButton      = findViewById(R.id.btn_inject)
        logView           = findViewById(R.id.log_view)
        autoInjectSwitch  = findViewById(R.id.switch_auto_inject)
        autoInjectSwitch.isChecked = vm.autoInject
        autoInjectSwitch.setOnCheckedChangeListener { _, checked ->
            vm.autoInject = checked
        }

        selectedPayloadCard = findViewById(R.id.selected_payload_card)
        selectedPayloadName = findViewById(R.id.selected_payload_name)
        selectedPayloadSize = findViewById(R.id.selected_payload_size)

        btnThemeToggle    = findViewById(R.id.btn_theme_toggle)
        btnLogToggle      = findViewById(R.id.btn_log_toggle)
        logSection        = findViewById(R.id.log_section)
        resultPanel       = findViewById(R.id.result_panel)
        resultPanelTitle  = findViewById(R.id.result_panel_title)
        resultPanelDetail = findViewById(R.id.result_panel_detail)
        btnResultDismiss  = findViewById(R.id.btn_result_dismiss)

        val recycler: RecyclerView = findViewById(R.id.payload_list)
        adapter = PayloadAdapter(
            onSelected = { payload ->
                vm.selectedPayload = payload
                updateInjectButton()
                showSelectedPayload(payload)
            },
            onDelete = { payload ->
                AlertDialog.Builder(this)
                    .setTitle("Delete payload")
                    .setMessage("Remove \"${payload.name}\" from custom payloads?")
                    .setPositiveButton("Delete") { _, _ ->
                        vm.deleteCustomPayload(payload)
                        if (vm.selectedPayload == null) {
                            selectedPayloadCard.visibility = View.GONE
                        }
                        updateInjectButton()
                    }
                    .setNegativeButton("Cancel", null)
                    .show()
            }
        )
        recycler.layoutManager = LinearLayoutManager(this)
        recycler.adapter = adapter

        btnThemeToggle.setOnClickListener {
            val prefs = getSharedPreferences(OmniRcmApp.PREFS_NAME, Context.MODE_PRIVATE)
            val isDark = prefs.getBoolean(OmniRcmApp.KEY_DARK_MODE, true)
            prefs.edit().putBoolean(OmniRcmApp.KEY_DARK_MODE, !isDark).apply()
            AppCompatDelegate.setDefaultNightMode(
                if (isDark) AppCompatDelegate.MODE_NIGHT_NO
                else        AppCompatDelegate.MODE_NIGHT_YES
            )
        }

        btnLogToggle.setOnClickListener {
            logVisible = !logVisible
            logSection.visibility = if (logVisible) View.VISIBLE else View.GONE
            if (logVisible) {
                val scrollView = findViewById<androidx.core.widget.NestedScrollView>(R.id.scroll_view)
                scrollView.post { scrollView.fullScroll(View.FOCUS_DOWN) }
            }
        }

        btnResultDismiss.setOnClickListener {
            resultPanel.visibility = View.GONE
            vm.clearLastResult()
        }

        injectButton.setOnClickListener {
            val payload = vm.selectedPayload ?: return@setOnClickListener
            val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
            val device = usbManager.deviceList.values.firstOrNull {
                it.vendorId == 0x0955 && it.productId == 0x7321
            } ?: return@setOnClickListener
            resultPanel.visibility = View.GONE
            vm.inject(device, payload)
        }

        findViewById<Button>(R.id.btn_fetch).setOnClickListener {
            vm.fetchPayloads()
        }

        findViewById<Button>(R.id.btn_add_custom).setOnClickListener {
            val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                type = "application/octet-stream"
                addCategory(Intent.CATEGORY_OPENABLE)
            }
            pickFileLauncher.launch(intent)
        }

        findViewById<Button>(R.id.btn_clear_log).setOnClickListener {
            vm.clearLog()
        }

        findViewById<Button>(R.id.btn_credits).setOnClickListener {
            showCredits()
        }

        vm.payloads.observe(this) { list ->
            adapter.submit(list)
            updateInjectButton()
        }

        vm.deviceConnected.observe(this) { connected ->
            if (connected) {
                pillDot.setBackgroundResource(R.drawable.dot_connected)
                pillStatus.text = getString(R.string.status_connected)
            } else {
                pillDot.setBackgroundResource(R.drawable.dot_disconnected)
                pillStatus.text = getString(R.string.status_waiting)
            }
            updateInjectButton()
        }

        vm.lastResult.observe(this) { status ->
            when (status) {
                MainViewModel.InjectionStatus.Success   -> {
                    pillDot.setBackgroundResource(R.drawable.dot_result_success)
                    pillStatus.text = getString(R.string.status_result_success)
                    showResultPanel(
                        getString(R.string.result_panel_title_success),
                        getString(R.string.result_panel_detail_success),
                        R.drawable.result_panel_background_success
                    )
                }
                MainViewModel.InjectionStatus.PatchedV1 -> {
                    pillDot.setBackgroundResource(R.drawable.dot_result_patched_v1)
                    pillStatus.text = getString(R.string.status_result_patched_v1)
                    showResultPanel(
                        getString(R.string.result_panel_title_patched_v1),
                        getText(R.string.result_panel_detail_patched_v1),
                        R.drawable.result_panel_background_patched_v1
                    )
                }
                MainViewModel.InjectionStatus.PatchedV2 -> {
                    pillDot.setBackgroundResource(R.drawable.dot_result_patched_v2)
                    pillStatus.text = getString(R.string.status_result_patched_v2)
                    showResultPanel(
                        getString(R.string.result_panel_title_patched_v2),
                        getString(R.string.result_panel_detail_patched_v2),
                        R.drawable.result_panel_background_patched_v2
                    )
                }
                MainViewModel.InjectionStatus.Error     -> {
                    pillDot.setBackgroundResource(R.drawable.dot_result_patched_v2)
                    pillStatus.text = getString(R.string.status_result_error)
                    showResultPanel(
                        getString(R.string.result_panel_title_error),
                        getString(R.string.result_panel_detail_error),
                        R.drawable.result_panel_background_error
                    )
                }
                MainViewModel.InjectionStatus.None      -> {
                    resultPanel.visibility = View.GONE
                    if (vm.deviceConnected.value == true) {
                        pillDot.setBackgroundResource(R.drawable.dot_connected)
                        pillStatus.text = getString(R.string.status_connected)
                    } else {
                        pillDot.setBackgroundResource(R.drawable.dot_disconnected)
                        pillStatus.text = getString(R.string.status_waiting)
                    }
                }
            }
        }

        vm.log.observe(this) { lines ->
            logView.text = lines.joinToString("\n")
            if (logVisible) {
                val scrollView = findViewById<androidx.core.widget.NestedScrollView>(R.id.scroll_view)
                scrollView.post { scrollView.fullScroll(View.FOCUS_DOWN) }
            }
        }

        vm.injecting.observe(this) { injecting ->
            injectButton.isEnabled = !injecting && canInject()
        }

        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == ACTION_USB_INJECT && vm.autoInject) {
            val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
            if (device != null) {
                val payload = vm.selectedPayload ?: vm.payloads.value?.firstOrNull()
                if (payload != null) {
                    vm.selectedPayload = payload
                    vm.inject(device, payload)
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        pollHandler.post(pollRunnable)
    }

    override fun onPause() {
        super.onPause()
        pollHandler.removeCallbacks(pollRunnable)
    }

    private fun canInject() =
        vm.selectedPayload != null && vm.deviceConnected.value == true

    private fun updateInjectButton() {
        injectButton.isEnabled = canInject() && vm.injecting.value != true
    }

    private fun showResultPanel(title: String, detail: CharSequence, backgroundRes: Int) {
        resultPanelTitle.text  = title
        resultPanelDetail.text = detail
        resultPanel.setBackgroundResource(backgroundRes)
        resultPanel.visibility = View.VISIBLE
        val scrollView = findViewById<androidx.core.widget.NestedScrollView>(R.id.scroll_view)
        scrollView.post { scrollView.fullScroll(View.FOCUS_DOWN) }
    }

    private fun importPayload(uri: Uri) {
        try {
            val rawName = uri.lastPathSegment?.substringAfterLast('/')
                ?: "custom_${System.currentTimeMillis()}.bin"
            val name = if (rawName.endsWith(".bin")) rawName else "$rawName.bin"
            val dest = File(io.github.omnircm.rcm.PayloadFetcher.customDir(), name)
            contentResolver.openInputStream(uri)?.use { src ->
                FileOutputStream(dest).use { src.copyTo(it) }
            }
            pendingSelectName = name
            vm.refreshPayloads()
            vm.logMessage("Added custom payload: $name")
        } catch (e: Exception) {
            vm.logMessage("[ERROR] Could not import payload: ${e.message}")
        }
    }

    private fun showSelectedPayload(payload: io.github.omnircm.data.Payload) {
        selectedPayloadCard.visibility = View.VISIBLE
        selectedPayloadName.text = payload.name
        selectedPayloadSize.text = "${String.format("%,d", payload.file.length())} bytes"
    }

    private fun showCredits() {
        val dialog = BottomSheetDialog(this)
        val view = layoutInflater.inflate(R.layout.bottom_sheet_credits, null)
        view.findViewById<android.widget.TextView>(R.id.credits_link).setOnClickListener {
            startActivity(Intent(Intent.ACTION_VIEW,
                Uri.parse("https://github.com/DefenderOfHyrule")))
        }
        view.findViewById<Button>(R.id.btn_check_updates).setOnClickListener {
            checkForUpdates()
        }
        dialog.setContentView(view)
        dialog.show()
    }

    private fun checkForUpdates() {
        Toast.makeText(this, R.string.update_checking, Toast.LENGTH_SHORT).show()
        lifecycleScope.launch {
            var failed = false
            val info = try {
                withContext(Dispatchers.IO) { UpdateChecker.check() }
            } catch (e: Exception) {
                failed = true
                null
            }
            if (failed) {
                Toast.makeText(this@MainActivity, R.string.update_error, Toast.LENGTH_SHORT).show()
                return@launch
            }
            if (info == null) {
                Toast.makeText(this@MainActivity, R.string.update_none, Toast.LENGTH_SHORT).show()
                return@launch
            }
            confirmDownload(info)
        }
    }

    private fun confirmDownload(info: UpdateInfo) {
        AlertDialog.Builder(this)
            .setTitle(R.string.update_available_title)
            .setMessage(getString(
                R.string.update_available_message,
                info.latestVersion.toString(),
                UpdateChecker.currentVersion().toString()
            ))
            .setPositiveButton(R.string.update_download) { _, _ -> downloadAndInstall(info) }
            .setNegativeButton(R.string.update_cancel, null)
            .show()
    }

    private fun downloadAndInstall(info: UpdateInfo) {
        vm.logMessage("Downloading update ${info.assetName}...")
        lifecycleScope.launch {
            val apkFile = try {
                withContext(Dispatchers.IO) {
                    UpdateChecker.downloadApk(info) { pct ->
                        if (pct % 10 == 0) vm.logMessage("  $pct%")
                    }
                }
            } catch (e: Exception) {
                vm.logMessage("[ERROR] Update download failed: ${e.message}")
                Toast.makeText(this@MainActivity, R.string.update_error, Toast.LENGTH_SHORT).show()
                return@launch
            }
            vm.logMessage("Update downloaded, launching installer...")
            promptInstall(apkFile)
        }
    }

    private fun promptInstall(apkFile: File) {
        if (!UpdateChecker.canRequestInstallPackages(this)) {
            AlertDialog.Builder(this)
                .setTitle(R.string.update_install_permission_title)
                .setMessage(R.string.update_install_permission_message)
                .setPositiveButton(R.string.update_install_permission_settings) { _, _ ->
                    val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        intent.data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                }
                .setNegativeButton(R.string.update_cancel, null)
                .show()
            return
        }
        startActivity(UpdateChecker.installIntent(this, apkFile))
    }

    companion object {
        const val ACTION_USB_INJECT = "io.github.omnircm.ACTION_USB_INJECT"
    }
}