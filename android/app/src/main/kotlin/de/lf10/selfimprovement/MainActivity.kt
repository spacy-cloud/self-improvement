package de.lf10.selfimprovement

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Steps from Health Connect (BS-97): a small channel that can only read step totals.
        flutterEngine.plugins.add(HealthStepsPlugin())
    }
}
