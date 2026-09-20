package com.mkdjj.whisnya

import android.content.Context
import android.content.Intent
import com.mkdjj.whisnya.qq.QqFlutterEngineHolder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var backupBridge: BackupFileBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        backupBridge = BackupFileBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (backupBridge?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        QqFlutterEngineHolder.getOrCreate()

    override fun shouldDestroyEngineWithHost(): Boolean = false
}
