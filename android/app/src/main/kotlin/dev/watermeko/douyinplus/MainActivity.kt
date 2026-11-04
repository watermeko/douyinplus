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

                "setCookies" -> {
                    val url = call.argument<String>("url") ?: "https://www.douyin.com"
                    val cookies = call.argument<Map<String, String>>("cookies")
                        ?: emptyMap()
                    val cookieManager = CookieManager.getInstance()
                    cookieManager.setAcceptCookie(true)
                    for ((name, value) in cookies) {
                        if (name.isBlank() || value.isEmpty()) continue
                        if (name.any { it == ';' || it == '=' || it.isWhitespace() }) continue
                        if (value.contains(';') || value.contains('\n')) continue
                        cookieManager.setCookie(
                            url,
                            "$name=$value; Path=/; Domain=.douyin.com; Secure; HttpOnly; SameSite=None",
                        )
                    }
                    cookieManager.flush()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }
}