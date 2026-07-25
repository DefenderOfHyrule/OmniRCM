package io.github.omnircm.ui

import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.content.Context
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import io.github.omnircm.OmniRcmApp
import io.github.omnircm.data.Payload
import io.github.omnircm.rcm.PayloadFetcher
import io.github.omnircm.rcm.RcmInjector
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainViewModel : ViewModel() {

    private val _payloads = MutableLiveData<List<Payload>>()
    val payloads: LiveData<List<Payload>> = _payloads

    private val _deviceConnected = MutableLiveData(false)
    val deviceConnected: LiveData<Boolean> = _deviceConnected

    private val _log = MutableLiveData<List<String>>(emptyList())
    val log: LiveData<List<String>> = _log

    private val _injecting = MutableLiveData(false)
    val injecting: LiveData<Boolean> = _injecting

    enum class InjectionStatus { None, Success, PatchedV1, PatchedV2, Error }
    private val _lastResult = MutableLiveData(InjectionStatus.None)
    val lastResult: LiveData<InjectionStatus> = _lastResult

    var selectedPayload: Payload? = null
    private val prefs = OmniRcmApp.instance
        .getSharedPreferences("omnircm_prefs", Context.MODE_PRIVATE)

    var autoInject: Boolean
        get() = prefs.getBoolean("auto_inject", false)
        set(value) { prefs.edit().putBoolean("auto_inject", value).apply() }

    init {
        refreshPayloads()
    }

    fun refreshPayloads() {
        _payloads.postValue(PayloadFetcher.getCachedPayloads() + PayloadFetcher.getCustomPayloads())
    }

    fun deleteCustomPayload(payload: Payload) {
        if (!payload.isCustom) return
        payload.file.delete()
        if (selectedPayload == payload) selectedPayload = null
        refreshPayloads()
    }

    fun fetchPayloads() {
        viewModelScope.launch(Dispatchers.IO) {
            appendLog("Fetching payloads...")
            try {
                PayloadFetcher.fetchAll { appendLog(it) }
                refreshPayloads()
                appendLog("Done.")
            } catch (e: Exception) {
                appendLog("[ERROR] ${e.message}")
            }
        }
    }

    fun pollDevice() {
        val usbManager = OmniRcmApp.instance.getSystemService(Context.USB_SERVICE) as UsbManager
        val connected = usbManager.deviceList.values.any { RcmInjector.isRcmDevice(it) }
        if (_deviceConnected.value != connected) {
            _deviceConnected.postValue(connected)
            if (!connected) _lastResult.postValue(InjectionStatus.None)
        }
    }

    fun inject(device: UsbDevice, payload: Payload) {
        if (_injecting.value == true) return
        _injecting.postValue(true)
        viewModelScope.launch(Dispatchers.IO) {
            try {
                appendLog("Injecting ${payload.name}...")
                val result = RcmInjector.inject(device, payload) { appendLog(it) }
                when (result) {
                    is RcmInjector.Result.Success   -> {
                        appendLog("✓ Injection successful, device ID: ${result.deviceId}")
                        _lastResult.postValue(InjectionStatus.Success)
                    }
                    is RcmInjector.Result.PatchedV1 -> {
                        appendLog("✗ Console is patched (V1 patched console), this console is not exploitable via RCM.")
                        _lastResult.postValue(InjectionStatus.PatchedV1)
                    }
                    is RcmInjector.Result.PatchedV2 -> {
                        appendLog("✗ Console is not exploitable via RCM (V2/Mariko console).")
                        _lastResult.postValue(InjectionStatus.PatchedV2)
                    }
                    is RcmInjector.Result.Error     -> {
                        appendLog("✗ ${result.message}")
                        _lastResult.postValue(InjectionStatus.Error)
                    }
                }
            } catch (e: Exception) {
                appendLog("[ERROR] ${e.message}")
            } finally {
                _injecting.postValue(false)
            }
        }
    }

    fun logMessage(line: String) = appendLog(line)

    fun clearLastResult() {
        RcmInjector.resetState()
        _lastResult.postValue(InjectionStatus.None)
    }

    private val logLines = mutableListOf<String>()

    private fun appendLog(line: String) {
        synchronized(logLines) { logLines.add(line) }
        _log.postValue(synchronized(logLines) { logLines.toList() })
    }

    fun clearLog() {
        synchronized(logLines) { logLines.clear() }
        _log.postValue(emptyList())
    }
}
