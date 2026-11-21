# Reviewed consumer rules for Mapbox Maps 11.31.3 / Common 24.31.3.
# Preserve the native JNI ABI, including all Mapbox class/member names.
# Method body optimization is safe while the complete native interface stays kept.
# Gson JNI only references these four JSON tree types; its own consumer rules
# continue to preserve reflective serialization and TypeToken signatures.
-keep,allowoptimization class com.google.gson.JsonArray { *; }
-keep,allowoptimization class com.google.gson.JsonElement { *; }
-keep,allowoptimization class com.google.gson.JsonObject { *; }
-keep,allowoptimization class com.google.gson.JsonPrimitive { *; }


# android-ndk27-11.31.3

-keep,allowoptimization class com.mapbox.geojson.** {*;}
-keep,allowoptimization class com.mapbox.bindgen.** {*;}
-keep,allowoptimization class !com.mapbox.maps.extension.**,!com.mapbox.maps.plugin.**,com.mapbox.maps.** {*;}
-keep,allowoptimization class com.mapbox.mapboxsdk.log.** {*;}
-keep,allowoptimization class com.mapbox.common.** {*;}
-keep,allowoptimization class com.mapbox.mapboxsdk.text.** {*;}

# common-ndk27-24.31.3
# The "class" keyword refers to any interface or class
-keep,allowoptimization class com.mapbox.bindgen.** {*;}
-keep,allowoptimization class com.mapbox.common.** {*;}

# GSON used by Bindgen


# GoogleActivityRecognition and GoogleLiveTrackingClient access GoogleApiAvailability
# using reflection to check Google Api availability.
-keep,allowoptimization class com.google.android.gms.common.GoogleApiAvailability {*;}

# GoogleDeviceLocationProvider and ProxyGoogleFusedLocationProviderClient access
# below classes using reflection so we need to keep them.
-keep,allowoptimization class com.google.android.gms.location.FusedLocationProviderClient {*;}

# GoogleActivityRecognition and ProxyGoogleActivityRecognitionClient access below classes using
# reflection so we need to keep them.
-keep,allowoptimization class com.google.android.gms.location.ActivityRecognition {*;}
-keep,allowoptimization class com.google.android.gms.location.ActivityRecognitionClient {*;}

# com.mapbox.common.module.cronet.LazyEngine uses reflection to check if CronetProviderInstaller is available
-keep,allowoptimization class com.google.android.gms.net.CronetProviderInstaller {*;}

# Ignore warnings about missing classes if the application does not use Google Play Services (com.google.android.gms.*)
-dontwarn com.google.android.gms.common.GoogleApiAvailability
-dontwarn com.google.android.gms.location.ActivityRecognition
-dontwarn com.google.android.gms.location.ActivityRecognitionClient
-dontwarn com.google.android.gms.location.ActivityRecognitionResult
-dontwarn com.google.android.gms.location.ActivityTransition$Builder
-dontwarn com.google.android.gms.location.ActivityTransition
-dontwarn com.google.android.gms.location.ActivityTransitionEvent
-dontwarn com.google.android.gms.location.ActivityTransitionRequest
-dontwarn com.google.android.gms.location.ActivityTransitionResult
-dontwarn com.google.android.gms.location.DetectedActivity
-dontwarn com.google.android.gms.location.FusedLocationProviderClient
-dontwarn com.google.android.gms.location.LocationCallback
-dontwarn com.google.android.gms.location.LocationRequest
-dontwarn com.google.android.gms.location.LocationResult
-dontwarn com.google.android.gms.location.LocationServices
-dontwarn com.google.android.gms.tasks.OnCanceledListener
-dontwarn com.google.android.gms.tasks.OnCompleteListener
-dontwarn com.google.android.gms.tasks.OnFailureListener
-dontwarn com.google.android.gms.tasks.OnSuccessListener
-dontwarn com.google.android.gms.tasks.RuntimeExecutionException
-dontwarn com.google.android.gms.tasks.Task
-dontwarn com.google.android.gms.net.CronetProviderInstaller

# Following ones are from OkHttp platform used only on JVM and when Conscrypt and other security providers are available.
-dontwarn org.bouncycastle.jsse.BCSSLParameters
-dontwarn org.bouncycastle.jsse.BCSSLSocket
-dontwarn org.bouncycastle.jsse.provider.BouncyCastleJsseProvider
-dontwarn org.conscrypt.Conscrypt$Version
-dontwarn org.conscrypt.Conscrypt
-dontwarn org.conscrypt.ConscryptHostnameVerifier
-dontwarn org.openjsse.javax.net.ssl.SSLParameters
-dontwarn org.openjsse.javax.net.ssl.SSLSocket
-dontwarn org.openjsse.net.ssl.OpenJSSE

