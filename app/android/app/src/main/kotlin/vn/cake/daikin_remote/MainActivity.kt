package vn.cake.daikin_remote

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Exposes the phone's IR blaster to Dart. Dart does all the Daikin encoding and passes finished
 * mark/space patterns, so this side never needs to know about protocols.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vn.cake.daikinremote/ir").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "hasEmitter" -> result.success(PhoneIr.hasEmitter(this))
                    "transmit" -> {
                        val err = PhoneIr.transmit(this, call.argument<Int>("freq")!!, call.pattern())
                        if (err == null) result.success(null) else result.error("IR", err, null)
                    }
                    "setTimer" -> {
                        IrTimers.set(
                            this,
                            call.argument<String>("slot")!!,
                            call.argument<Number>("seconds")!!.toLong(),
                            call.argument<Int>("freq")!!,
                            call.pattern(),
                        )
                        result.success(null)
                    }
                    "cancelTimer" -> {
                        IrTimers.cancel(this, call.argument<String>("slot")!!)
                        result.success(null)
                    }
                    "timers" -> result.success(IrTimers.status(this))
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("IR", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    private fun io.flutter.plugin.common.MethodCall.pattern(): IntArray =
        argument<List<Number>>("pattern")!!.map { it.toInt() }.toIntArray()
}
