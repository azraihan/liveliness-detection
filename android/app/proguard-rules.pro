# PyTorch Mobile (pytorch_android_lite) is loaded through JNI, which looks classes
# up by their string names. R8 cannot see those references, so without these rules
# it strips org.pytorch.PyTorchAndroid and renames the rest — and System.loadLibrary
# then dies with ClassNotFoundException inside LiteNativePeer's static initialiser.
-keep class org.pytorch.** { *; }
-keepclassmembers class org.pytorch.** { *; }
-dontwarn org.pytorch.**

# fbjni and SoLoader back PyTorch's native bridge and are likewise reached by name.
-keep class com.facebook.jni.** { *; }
-keep class com.facebook.soloader.** { *; }
-dontwarn com.facebook.jni.**
-dontwarn com.facebook.soloader.**

# Any class holding an fbjni HybridData is instantiated from native code.
-keepclasseswithmembernames class * {
    native <methods>;
}
