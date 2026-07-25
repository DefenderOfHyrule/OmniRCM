-keep class io.github.omnircm.rcm.RcmInjector { native <methods>; }
-keep class io.github.omnircm.data.** { *; }
-keepclassmembers class * {
    @com.squareup.moshi.Json <fields>;
}
