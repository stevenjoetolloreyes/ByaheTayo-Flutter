package com.estudyantego.app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val walkingChannelName = "byahetayo/walking_steps"
    private var sensorManager: SensorManager? = null
    private var stepSensor: Sensor? = null

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
    }
}
