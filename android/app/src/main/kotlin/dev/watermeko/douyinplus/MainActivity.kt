package dev.watermeko.douyinplus

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "dev.watermeko.douyinplus/cookies"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCookieHeader" -> {
                    val url = call.argument<String>("url") ?: "https://www.douyin.com"
                    val cookieManager = CookieManager.getInstance()
                    cookieManager.setAcceptCookie(true)
                    result.success(cookieManager.getCookie(url))
                }

                "removeAllCookies" -> {
                    val cookieManager = CookieManager.getInstance()
                    cookieManager.removeAllCookies {
                        cookieManager.flush()
                        result.success(true)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}