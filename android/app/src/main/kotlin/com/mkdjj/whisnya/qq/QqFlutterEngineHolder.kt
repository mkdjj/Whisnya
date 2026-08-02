package com.mkdjj.whisnya.qq

import android.app.Application
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

object QqFlutterEngineHolder {
    const val CACHE_KEY = "whisnya_main_engine"

    @Volatile
    private var application: Application? = null

    @Volatile
    private var engine: FlutterEngine? = null

    @Synchronized
    fun initialize(value: Application) {
        if (application == null) application = value
    }

    @Synchronized
    fun getOrCreate(): FlutterEngine {
        engine?.let { return it }
        val app = requireNotNull(application) { "QqFlutterEngineHolder is not initialized" }
        FlutterInjector.instance().flutterLoader().startInitialization(app)
        FlutterInjector.instance().flutterLoader().ensureInitializationComplete(app, null)
        return FlutterEngine(app).also { created ->
            QqBridgeChannels.attach(app, created)
            created.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
            FlutterEngineCache.getInstance().put(CACHE_KEY, created)
            engine = created
        }
    }
}
