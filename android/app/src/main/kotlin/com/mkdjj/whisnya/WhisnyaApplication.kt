package com.mkdjj.whisnya

import android.app.Application
import com.mkdjj.whisnya.qq.QqFlutterEngineHolder

class WhisnyaApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        QqFlutterEngineHolder.initialize(this)
    }
}
