package com.estudyantego.app

import android.content.Context
import android.os.Bundle
import android.os.Build
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.view.Surface
import androidx.activity.result.ActivityResultLauncher
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterFragmentActivity() {
    private val walkingChannelName = "byahetayo/walking_steps"
    private var sensorManager: SensorManager? = null
    private var stepSensor: Sensor? = null

    // Compass heading for Live Follow (Nov 13, 2026 — built-in,
    // no plugin): the magnetometer / rotation-vector sensor is
    // read here over the "com.estudyantego.app/compass"
    // EventChannel, so no flutter_compass dependency (its AAR
    // was compiled against compileSdk 33 while its androidx deps
    // need 34+, which failed the Actions build at
    // checkReleaseAarMetadata). Prefer TYPE_ROTATION_VECTOR;
    // fall back to accelerometer + magnetometer when it is
    // absent. Events are maps: {"heading": degrees 0–360
    // (0 = north), "accuracy": sensor status int 0–3, absent
    // until the system has reported one}. The listener is only
    // registered while Dart is listening (Live Follow only);
    // onCancel unregisters it, so there is no background drain.
    private val compassChannelName = "com.estudyantego.app/compass"

    // Health Connect fallback for the Walking Goal (Nov 5, 2026):
    // today's steps from Health Connect on phones with no
    // TYPE_STEP_COUNTER sensor. The sensor path above always wins
    // when the sensor exists; this channel is only consulted
    // when it does not. The permission flow opens the Health
    // Connect UI (never a runtime permission dialog), so the
    // MethodChannel result for "requestStepsPermission" is held
    // until the user finishes that flow.
    private val healthConnectChannelName = "byahetayo/health_connect_steps"
    private val healthConnectScope =
        CoroutineScope(Dispatchers.Main + SupervisorJob())
    private lateinit var healthConnectPermissionLauncher:
        ActivityResultLauncher<Set<String>>
    private var pendingHealthConnectResult: MethodChannel.Result? = null

    // Production diagnostics log — ONE logging system, shared with
    // the Dart side. Both layers append JSON lines (the exact
    // ErrorLogEntry fields) to the same file:
    // <external files dir>/estudyantego-crash.log, i.e.
    // Android/data/com.estudyantego.app/files/estudyantego-crash.log.
    // No storage permission is needed for the app's own external
    // files dir. This replaces the earlier plain-text file-logger
    // format; it does not run a second logger beside the Dart one.
    // Every write is guarded and never throws.
    //
    // Honest limits: this handler runs from MainActivity.onCreate
    // onward. It does NOT capture provider crashes before
    // Application, native signals (SIGSEGV), or native library load
    // failures — for those, the file will be empty or marker-only,
    // which is itself evidence of where the crash sits.

    override fun onCreate(savedInstanceState: Bundle?) {
        writeEntry(
            category = "startup",
            message = "Activity started.",
            startupStage = "activity_start",
            severity = "info",
            stackTrace = null,
        )
        installCrashHandler()
        super.onCreate(savedInstanceState)
        // Health Connect permission flow: the launcher must be
        // registered before the activity starts; its callback
        // completes the pending MethodChannel result.
        healthConnectPermissionLauncher = registerForActivityResult(
            PermissionController.createRequestPermissionResultContract()
        ) { granted ->
            val result = pendingHealthConnectResult
            pendingHealthConnectResult = null
            try {
                result?.success(
                    granted.contains(
                        HealthPermission.getReadPermission(
                            StepsRecord::class
                        )
                    )
                )
            } catch (_: Exception) {
                // A dead result must never crash the callback.
            }
        }
    }

    override fun onDestroy() {
        healthConnectScope.cancel()
        super.onDestroy()
    }

    // --- Built-in compass helpers (Nov 13, 2026) -----------------
    // Heading in degrees, 0–360 (0 = north), from a rotation
    // vector, with the display rotation compensated so the
    // heading matches the way the phone is held.
    private fun compassHeadingFromRotationVector(
        values: FloatArray
    ): Double {
        val matrix = FloatArray(9)
        SensorManager.getRotationMatrixFromVector(matrix, values)
        return compassHeadingFromRotationMatrix(matrix)
    }

    // Heading from an accelerometer + magnetometer pair (the
    // fallback when there is no rotation-vector sensor). Null
    // when either reading is missing or no rotation matrix can
    // be computed from them.
    private fun compassHeadingFromAccelMagnet(
        accel: FloatArray?,
        magnet: FloatArray?
    ): Double? {
        if (accel == null || magnet == null) return null
        val matrix = FloatArray(9)
        if (!SensorManager.getRotationMatrix(
                matrix, null, accel, magnet
            )
        ) {
            return null
        }
        return compassHeadingFromRotationMatrix(matrix)
    }

    private fun compassHeadingFromRotationMatrix(
        matrix: FloatArray
    ): Double {
        val remapped = FloatArray(9)
        when (compassDisplayRotation()) {
            Surface.ROTATION_90 ->
                SensorManager.remapCoordinateSystem(
                    matrix,
                    SensorManager.AXIS_Y,
                    SensorManager.AXIS_MINUS_X,
                    remapped
                )
            Surface.ROTATION_180 ->
                SensorManager.remapCoordinateSystem(
                    matrix,
                    SensorManager.AXIS_MINUS_X,
                    SensorManager.AXIS_MINUS_Y,
                    remapped
                )
            Surface.ROTATION_270 ->
                SensorManager.remapCoordinateSystem(
                    matrix,
                    SensorManager.AXIS_MINUS_Y,
                    SensorManager.AXIS_X,
                    remapped
                )
            else -> matrix.copyInto(remapped)
        }
        val orientation = FloatArray(3)
        SensorManager.getOrientation(remapped, orientation)
        return (Math.toDegrees(orientation[0].toDouble()) + 360) % 360
    }

    // Light low-pass so one noisy accel / magnetometer sample
    // cannot swing the heading (the Dart side low-passes again).
    private fun lowPassCompass(
        input: FloatArray,
        output: FloatArray?
    ): FloatArray {
        val out = output ?: FloatArray(input.size)
        val alpha = 0.25f
        for (i in input.indices) {
            out[i] = out[i] + alpha * (input[i] - out[i])
        }
        return out
    }

    @Suppress("DEPRECATION")
    private fun compassDisplayRotation(): Int {
        return try {
            windowManager.defaultDisplay?.rotation ?: Surface.ROTATION_0
        } catch (_: Exception) {
            Surface.ROTATION_0
        }
    }

    private fun crashLogFile(): File? {
        return try {
            getExternalFilesDir(null)?.let { File(it, "estudyantego-crash.log") }
        } catch (_: Exception) {
            null
        }
    }

    private fun isoNow(): String {
        return try {
            val format = SimpleDateFormat(
                "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                Locale.US,
            )
            format.timeZone = TimeZone.getTimeZone("UTC")
            format.format(Date())
        } catch (_: Exception) {
            ""
        }
    }

    private fun appVersion(): String {
        return try {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0)?.versionName
                ?: "unknown"
        } catch (_: Exception) {
            "unknown"
        }
    }

    private fun appBuildNumber(): String {
        return try {
            @Suppress("DEPRECATION")
            val info = packageManager.getPackageInfo(packageName, 0)
            if (Build.VERSION.SDK_INT >= 28) {
                info.longVersionCode.toString()
            } else {
                info.versionCode.toString()
            }
        } catch (_: Exception) {
            "unknown"
        }
    }

    // Same redaction policy as the Dart side: values keyed as
    // passwords, tokens, keys, secrets, or authorisation material are
    // replaced before storage. Stack frames and class names are kept.
    private fun redact(text: String): String {
        var out = text
        try {
            out = out.replace(
                Regex(
                    "(?i)(password|passwd|pwd|token|api[_-]?key|secret|authorization|auth[_-]?token|id[_-]?token|refresh[_-]?token)\\s*[:=]\\s*[^\\s,'\"}\\]]+",
                ),
                "$1: [REDACTED]",
            )
            out = out.replace(
                Regex("(?i)Bearer\\s+[A-Za-z0-9._\\-]+"),
                "Bearer [REDACTED]",
            )
        } catch (_: Exception) {
            // Redaction failure must never block logging.
        }
        return out
    }

    private fun writeEntry(
        category: String,
        message: String,
        startupStage: String?,
        severity: String,
        stackTrace: String?,
    ) {
        try {
            val file = crashLogFile() ?: return
            file.parentFile?.mkdirs()
            val entry = JSONObject()
            entry.put("id", UUID.randomUUID().toString())
            entry.put("timestampUtc", isoNow())
            entry.put("category", category)
            entry.put("message", redact(message))
            if (stackTrace != null) {
                entry.put("stackTrace", redact(stackTrace))
            } else {
                entry.put("stackTrace", JSONObject.NULL)
            }
            if (startupStage != null) {
                entry.put("startupStage", startupStage)
            } else {
                entry.put("startupStage", JSONObject.NULL)
            }
            entry.put("appVersion", appVersion())
            entry.put("buildNumber", appBuildNumber())
            entry.put("androidVersion", Build.VERSION.RELEASE ?: "unknown")
            entry.put("deviceModel", Build.MODEL ?: "unknown")
            entry.put("severity", severity)
            FileWriter(file, true).use { writer ->
                writer.write(entry.toString())
                writer.write("\n")
            }
        } catch (_: Exception) {
            // Logger must never throw.
        }
    }

    private fun installCrashHandler() {
        if (crashHandlerInstalled) return
        crashHandlerInstalled = true
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val stack = StringBuilder()
                var cause: Throwable? = throwable
                while (cause != null) {
                    stack.append(cause.toString()).append("\n")
                    cause.stackTrace.forEach { element ->
                        stack.append("    at ").append(element).append("\n")
                    }
                    cause = cause.cause
                    if (cause != null) {
                        stack.append("Caused by: ").append(cause).append("\n")
                    }
                }
                writeEntry(
                    category = "native",
                    message = "Uncaught exception on thread ${thread.name}: $throwable",
                    startupStage = null,
                    severity = "fatal",
                    stackTrace = stack.toString(),
                )
            } catch (_: Exception) {
                // Logger must never throw, even while crashing.
            }
            if (previous != null) {
                previous.uncaughtException(thread, throwable)
            } else {
                android.os.Process.killProcess(android.os.Process.myPid())
                System.exit(10)
            }
        }
    }

    companion object {
        @Volatile
        private var crashHandlerInstalled = false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sensorManager =
            getSystemService(Context.SENSOR_SERVICE) as SensorManager
        stepSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            walkingChannelName
        ).setMethodCallHandler { call, result ->
            if (call.method == "isAvailable") {
                result.success(stepSensor != null)
            } else {
                result.notImplemented()
            }
        }
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            walkingChannelName
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var listener: SensorEventListener? = null

                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink
                ) {
                    val sensor = stepSensor
                    if (sensor == null) {
                        events.error(
                            "UNAVAILABLE",
                            "Step counter sensor not available",
                            null
                        )
                        return
                    }
                    listener = object : SensorEventListener {
                        override fun onSensorChanged(event: SensorEvent) {
                            // Cumulative steps since boot; the Dart
                            // side converts this to daily deltas.
                            events.success(event.values[0].toInt())
                        }

                        override fun onAccuracyChanged(
                            sensor: Sensor?,
                            accuracy: Int
                        ) {
                        }
                    }
                    sensorManager?.registerListener(
                        listener,
                        sensor,
                        SensorManager.SENSOR_DELAY_NORMAL
                    )
                }

                override fun onCancel(arguments: Any?) {
                    listener?.let { sensorManager?.unregisterListener(it) }
                    listener = null
                }
            }
        )
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            compassChannelName
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var listener: SensorEventListener? = null
                // Last accuracy the system reported for the sensor
                // we actually read from (null = not reported yet;
                // the Dart side accepts a missing accuracy).
                private var lastAccuracy: Int? = null
                private var accelReading: FloatArray? = null
                private var magnetReading: FloatArray? = null

                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink
                ) {
                    val manager = sensorManager
                    if (manager == null) {
                        events.error(
                            "UNAVAILABLE",
                            "Sensor service not available",
                            null
                        )
                        return
                    }
                    val rotationVector = manager.getDefaultSensor(
                        Sensor.TYPE_ROTATION_VECTOR
                    )
                    val accelerometer = manager.getDefaultSensor(
                        Sensor.TYPE_ACCELEROMETER
                    )
                    val magneticField = manager.getDefaultSensor(
                        Sensor.TYPE_MAGNETIC_FIELD
                    )
                    if (rotationVector == null &&
                        (accelerometer == null || magneticField == null)
                    ) {
                        events.error(
                            "UNAVAILABLE",
                            "No compass sensor on this device",
                            null
                        )
                        return
                    }
                    val useRotationVector = rotationVector != null
                    listener = object : SensorEventListener {
                        override fun onSensorChanged(event: SensorEvent) {
                            val heading = when {
                                useRotationVector &&
                                    event.sensor.type ==
                                        Sensor.TYPE_ROTATION_VECTOR -> {
                                    compassHeadingFromRotationVector(
                                        event.values
                                    )
                                }
                                !useRotationVector &&
                                    event.sensor.type ==
                                        Sensor.TYPE_ACCELEROMETER -> {
                                    accelReading = lowPassCompass(
                                        event.values,
                                        accelReading
                                    )
                                    compassHeadingFromAccelMagnet(
                                        accelReading,
                                        magnetReading
                                    )
                                }
                                !useRotationVector &&
                                    event.sensor.type ==
                                        Sensor.TYPE_MAGNETIC_FIELD -> {
                                    magnetReading = lowPassCompass(
                                        event.values,
                                        magnetReading
                                    )
                                    compassHeadingFromAccelMagnet(
                                        accelReading,
                                        magnetReading
                                    )
                                }
                                else -> null
                            } ?: return
                            if (heading.isNaN()) return
                            val payload = HashMap<String, Any>()
                            payload["heading"] = heading
                            lastAccuracy?.let {
                                payload["accuracy"] = it
                            }
                            try {
                                events.success(payload)
                            } catch (_: Exception) {
                                // A dead sink must never crash the
                                // sensor thread.
                            }
                        }

                        override fun onAccuracyChanged(
                            sensor: Sensor?,
                            accuracy: Int
                        ) {
                            // Only the sensor we read from counts:
                            // the rotation-vector path reports its
                            // own accuracy, the fallback path the
                            // magnetometer's.
                            if (useRotationVector &&
                                sensor?.type ==
                                    Sensor.TYPE_ROTATION_VECTOR
                            ) {
                                lastAccuracy = accuracy
                            } else if (!useRotationVector &&
                                sensor?.type ==
                                    Sensor.TYPE_MAGNETIC_FIELD
                            ) {
                                lastAccuracy = accuracy
                            }
                        }
                    }
                    val active = listener ?: return
                    if (useRotationVector) {
                        manager.registerListener(
                            active,
                            rotationVector,
                            SensorManager.SENSOR_DELAY_GAME
                        )
                    } else {
                        manager.registerListener(
                            active,
                            accelerometer,
                            SensorManager.SENSOR_DELAY_GAME
                        )
                        manager.registerListener(
                            active,
                            magneticField,
                            SensorManager.SENSOR_DELAY_GAME
                        )
                    }
                }

                override fun onCancel(arguments: Any?) {
                    listener?.let {
                        sensorManager?.unregisterListener(it)
                    }
                    listener = null
                    lastAccuracy = null
                    accelReading = null
                    magnetReading = null
                }
            }
        )
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            healthConnectChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Plain string, never a raw SDK int: the Dart side
                // must not guess at HealthConnectClient's constants.
                "getSdkStatus" -> {
                    val status = HealthConnectClient.getSdkStatus(this)
                    result.success(
                        when (status) {
                            HealthConnectClient.SDK_AVAILABLE -> "available"
                            HealthConnectClient
                                .SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED ->
                                "updateRequired"
                            else -> "unavailable"
                        }
                    )
                }
                "hasStepsPermission" -> {
                    healthConnectScope.launch {
                        try {
                            if (HealthConnectClient.getSdkStatus(
                                    this@MainActivity
                                ) != HealthConnectClient.SDK_AVAILABLE
                            ) {
                                result.success(false)
                                return@launch
                            }
                            val client = HealthConnectClient.getOrCreate(
                                this@MainActivity
                            )
                            val granted = client.permissionController
                                .getGrantedPermissions()
                            result.success(
                                granted.contains(
                                    HealthPermission.getReadPermission(
                                        StepsRecord::class
                                    )
                                )
                            )
                        } catch (_: Exception) {
                            // Any failure reads as "not granted" — the
                            // Dart side shows the connect prompt, never
                            // a fabricated step count.
                            result.success(false)
                        }
                    }
                }
                "requestStepsPermission" -> {
                    try {
                        if (HealthConnectClient.getSdkStatus(this) !=
                            HealthConnectClient.SDK_AVAILABLE
                        ) {
                            result.success(false)
                        } else {
                            // A previous request still in flight is
                            // answered as denied rather than left
                            // hanging forever.
                            pendingHealthConnectResult?.let { old ->
                                try {
                                    old.success(false)
                                } catch (_: Exception) {
                                }
                            }
                            pendingHealthConnectResult = result
                            healthConnectPermissionLauncher.launch(
                                setOf(
                                    HealthPermission.getReadPermission(
                                        StepsRecord::class
                                    )
                                )
                            )
                        }
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "readTodaySteps" -> {
                    val startMillis =
                        call.argument<Number>("startMillis")?.toLong()
                    val endMillis =
                        call.argument<Number>("endMillis")?.toLong()
                    healthConnectScope.launch {
                        try {
                            if (startMillis == null || endMillis == null ||
                                endMillis <= startMillis ||
                                HealthConnectClient.getSdkStatus(
                                    this@MainActivity
                                ) != HealthConnectClient.SDK_AVAILABLE
                            ) {
                                result.error(
                                    "INVALID_RANGE",
                                    "Invalid Health Connect read range",
                                    null
                                )
                                return@launch
                            }
                            val client = HealthConnectClient.getOrCreate(
                                this@MainActivity
                            )
                            val granted = client.permissionController
                                .getGrantedPermissions()
                            if (!granted.contains(
                                    HealthPermission.getReadPermission(
                                        StepsRecord::class
                                    )
                                )
                            ) {
                                result.error(
                                    "PERMISSION_DENIED",
                                    "Steps permission not granted",
                                    null
                                )
                                return@launch
                            }
                            // Aggregate of StepsRecord for today
                            // (Manila midnight -> now, supplied by the
                            // Dart side so the day matches the app's
                            // Manila date key). A zero here is real
                            // data — no steps recorded in the window.
                            val response = client.aggregate(
                                AggregateRequest(
                                    metrics = setOf(
                                        StepsRecord.COUNT_TOTAL
                                    ),
                                    timeRangeFilter =
                                        TimeRangeFilter.between(
                                            Instant.ofEpochMilli(
                                                startMillis
                                            ),
                                            Instant.ofEpochMilli(endMillis),
                                        ),
                                )
                            )
                            val steps =
                                response[StepsRecord.COUNT_TOTAL] ?: 0L
                            result.success(steps.toInt())
                        } catch (_: Exception) {
                            result.error(
                                "READ_FAILED",
                                "Could not read steps from Health Connect",
                                null
                            )
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
