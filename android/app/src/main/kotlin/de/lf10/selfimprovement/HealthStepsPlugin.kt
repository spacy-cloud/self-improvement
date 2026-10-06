package de.lf10.selfimprovement

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * The Android side of "Schritte aus Health übernehmen" (BS-97, decision D-031): a small channel to
 * Health Connect that can only READ the aggregated step total of a time range.
 *
 * There is no method that writes, and none for another kind of data. The app asks for exactly one
 * permission, `android.permission.health.READ_STEPS`, and only the system dialog of Health Connect
 * can grant it. Totals come from Health Connect's own aggregation, which merges several sources
 * (phone, watch, apps); this class never reads single records and never adds anything up.
 *
 * Channel `de.lf10.selfimprovement/health_steps`:
 * - `availability` -> `available`, `updateRequired` or `missing`
 * - `hasAccess` -> true when the steps may be read (never shows a dialog)
 * - `requestAccess` -> true when the steps may be read after the system dialog
 * - `totalSteps` (`startUtcMillis`, `endUtcMillis`) -> the aggregated total, or null without data
 * - `openInstallPage`, `openAccessSettings` -> true when a page was opened
 *
 * Errors carry only a code (`access_denied`, `failed`, `busy`, `no_activity`) and the class name of
 * the cause as details, never a message (messages can contain values).
 */
class HealthStepsPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {

    private var context: Context? = null
    private var channel: MethodChannel? = null
    private var scope: CoroutineScope? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingAccessResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler(this)
        channel = methodChannel
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        scope?.cancel()
        scope = null
        context = null
        failPendingAccess()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        // The activity is recreated: an open dialog still delivers its result to the new one.
        releaseActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        releaseActivity()
        failPendingAccess()
    }

    private fun releaseActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    /** Ends an open request when its screen is gone for good, so the next one is not "busy". */
    private fun failPendingAccess() {
        val pending = pendingAccessResult ?: return
        pendingAccessResult = null
        pending.error(ERROR_NO_ACTIVITY, null, null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "availability" -> {
                try {
                    result.success(availability(requireContext()))
                } catch (error: Exception) {
                    result.error(ERROR_FAILED, error.javaClass.simpleName, null)
                }
            }
            "hasAccess" -> launch(result) { hasAccess(requireContext()) }
            "requestAccess" -> requestAccess(result)
            "totalSteps" -> {
                val start = call.argument<Number>("startUtcMillis")?.toLong()
                val end = call.argument<Number>("endUtcMillis")?.toLong()
                if (start == null || end == null) {
                    result.error(ERROR_FAILED, null, null)
                } else {
                    launch(result) { totalSteps(requireContext(), start, end) }
                }
            }
            "openInstallPage" -> result.success(openInstallPage())
            "openAccessSettings" -> result.success(openAccessSettings())
            else -> result.notImplemented()
        }
    }

    // ------------------------------------------------------------------ state

    private fun availability(appContext: Context): String =
        when (HealthConnectClient.getSdkStatus(appContext)) {
            HealthConnectClient.SDK_AVAILABLE -> "available"
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "updateRequired"
            else -> "missing"
        }

    private suspend fun hasAccess(appContext: Context): Boolean {
        val client = HealthConnectClient.getOrCreate(appContext)
        return client.permissionController.getGrantedPermissions().contains(STEPS_PERMISSION)
    }

    // ------------------------------------------------------------- the dialog

    /**
     * Starts the system dialog of Health Connect. The result arrives in [onActivityResult]. Only
     * one request can be open at a time.
     */
    private fun requestAccess(result: MethodChannel.Result) {
        val host = activity
        if (host == null) {
            result.error(ERROR_NO_ACTIVITY, null, null)
            return
        }
        if (pendingAccessResult != null) {
            result.error(ERROR_BUSY, null, null)
            return
        }
        try {
            val contract = PermissionController.createRequestPermissionResultContract()
            val intent = contract.createIntent(host, setOf(STEPS_PERMISSION))
            pendingAccessResult = result
            host.startActivityForResult(intent, REQUEST_CODE_ACCESS)
        } catch (error: ActivityNotFoundException) {
            pendingAccessResult = null
            result.success(false)
        } catch (error: Exception) {
            pendingAccessResult = null
            result.error(ERROR_FAILED, error.javaClass.simpleName, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE_ACCESS) {
            return false
        }
        val pending = pendingAccessResult ?: return true
        pendingAccessResult = null
        val granted =
            try {
                PermissionController.createRequestPermissionResultContract()
                    .parseResult(resultCode, data)
                    .contains(STEPS_PERMISSION)
            } catch (error: Exception) {
                false
            }
        pending.success(granted)
        return true
    }

    // --------------------------------------------------------------- the read

    /**
     * The total of Health Connect's own aggregation for `[start, end)`. `null` means there is no
     * step data in the range, which is not the same as 0.
     */
    private suspend fun totalSteps(appContext: Context, startMillis: Long, endMillis: Long): Long? {
        val client = HealthConnectClient.getOrCreate(appContext)
        val response =
            client.aggregate(
                AggregateRequest(
                    metrics = setOf(StepsRecord.COUNT_TOTAL),
                    timeRangeFilter =
                        TimeRangeFilter.between(
                            Instant.ofEpochMilli(startMillis),
                            Instant.ofEpochMilli(endMillis),
                        ),
                )
            )
        return response[StepsRecord.COUNT_TOTAL]
    }

    // ------------------------------------------------------------ system pages

    /** The page of Health Connect in the store (installing it, or updating it). */
    private fun openInstallPage(): Boolean {
        val host: Context = activity ?: context ?: return false
        val intent =
            Intent(Intent.ACTION_VIEW).apply {
                setPackage(STORE_PACKAGE)
                data =
                    Uri.parse(
                        "market://details?id=$PROVIDER_PACKAGE&url=healthconnect%3A%2F%2Fonboarding"
                    )
                putExtra("overlay", true)
                putExtra("callerId", host.packageName)
            }
        return startPage(host, intent)
    }

    /** The settings of Health Connect, where the access of this app can be allowed. */
    private fun openAccessSettings(): Boolean {
        val host: Context = activity ?: context ?: return false
        return startPage(host, Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS))
    }

    private fun startPage(host: Context, intent: Intent): Boolean {
        if (host !is Activity) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            host.startActivity(intent)
            true
        } catch (error: ActivityNotFoundException) {
            false
        } catch (error: SecurityException) {
            false
        }
    }

    // ----------------------------------------------------------------- helpers

    private fun requireContext(): Context =
        context ?: throw IllegalStateException("not attached to the engine")

    /** Runs [block] and sends its value, or a typed error without a message, to [result]. */
    private fun launch(result: MethodChannel.Result, block: suspend () -> Any?) {
        val running = scope
        if (running == null) {
            result.error(ERROR_FAILED, null, null)
            return
        }
        running.launch {
            try {
                result.success(block())
            } catch (error: CancellationException) {
                throw error
            } catch (error: SecurityException) {
                result.error(ERROR_ACCESS_DENIED, error.javaClass.simpleName, null)
            } catch (error: Exception) {
                result.error(ERROR_FAILED, error.javaClass.simpleName, null)
            }
        }
    }

    private companion object {
        const val CHANNEL = "de.lf10.selfimprovement/health_steps"
        const val REQUEST_CODE_ACCESS = 4917
        const val PROVIDER_PACKAGE = "com.google.android.apps.healthdata"
        const val STORE_PACKAGE = "com.android.vending"
        const val ERROR_ACCESS_DENIED = "access_denied"
        const val ERROR_FAILED = "failed"
        const val ERROR_BUSY = "busy"
        const val ERROR_NO_ACTIVITY = "no_activity"

        /** The only permission the app asks for: reading steps. */
        val STEPS_PERMISSION: String = HealthPermission.getReadPermission(StepsRecord::class)
    }
}
