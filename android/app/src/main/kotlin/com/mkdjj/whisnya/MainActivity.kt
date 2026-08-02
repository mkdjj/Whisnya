package com.mkdjj.whisnya

import android.content.Context
import com.mkdjj.whisnya.qq.QqFlutterEngineHolder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        QqFlutterEngineHolder.getOrCreate()

    override fun shouldDestroyEngineWithHost(): Boolean = false
}
