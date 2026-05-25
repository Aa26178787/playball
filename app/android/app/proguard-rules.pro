-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }
-keep class com.kakao.** { *; }
-dontwarn com.pichillilorenzo.flutter_inappwebview.**

# webview_flutter JavaScript bridge
-keep class io.flutter.plugins.webviewflutter.** { *; }
-dontwarn io.flutter.plugins.webviewflutter.**

# @JavascriptInterface 메서드 보호
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
