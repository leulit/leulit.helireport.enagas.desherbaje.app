package com.leulit.enagas

import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onResume() {
        super.onResume()
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }
}
