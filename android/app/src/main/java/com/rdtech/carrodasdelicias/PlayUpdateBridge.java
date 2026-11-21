package com.rdtech.carrodasdelicias;

import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.IntentSenderRequest;
import androidx.activity.result.contract.ActivityResultContracts;
import com.google.android.play.core.appupdate.AppUpdateManager;
import com.google.android.play.core.appupdate.AppUpdateManagerFactory;
import com.google.android.play.core.appupdate.AppUpdateOptions;
import com.google.android.play.core.install.model.AppUpdateType;
import com.google.android.play.core.install.model.UpdateAvailability;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.util.HashMap;
import java.util.Map;

/** Uses the offer returned by Google Play for this installation and account. */
final class PlayUpdateBridge {
    private final MainActivity activity;
    private final AppUpdateManager manager;
    private final MethodChannel channel;
    private final ActivityResultLauncher<IntentSenderRequest> launcher;
    private MethodChannel.Result pendingUpdate;

    PlayUpdateBridge(MainActivity activity, FlutterEngine engine) {
        this.activity = activity;
        manager = AppUpdateManagerFactory.create(activity);
        launcher = activity.registerForActivityResult(
                new ActivityResultContracts.StartIntentSenderForResult(), result -> {
                    MethodChannel.Result pending = pendingUpdate;
                    pendingUpdate = null;
                    if (pending != null) pending.success(result.getResultCode() == MainActivity.RESULT_OK);
                });
        channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),
                "com.rdtech.carrodasdelicias/updates");
        channel.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "getInstallation":
                    installation(result);
                    break;
                case "checkForUpdate":
                    manager.getAppUpdateInfo().addOnSuccessListener(info -> {
                        Map<String, Object> values = new HashMap<>();
                        values.put("availability", info.updateAvailability());
                        values.put("versionCode", info.availableVersionCode());
                        values.put("immediateAllowed", info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE));
                        result.success(values);
                    }).addOnFailureListener(error -> result.error("PLAY_CHECK_FAILED", "Não foi possível consultar a Play Store.", null));
                    break;
                case "startImmediateUpdate":
                    if (pendingUpdate != null) {
                        result.error("UPDATE_RUNNING", "Atualização já iniciada.", null);
                        break;
                    }
                    pendingUpdate = result;
                    // AppUpdateInfo may be used only once. Always fetch a fresh offer.
                    manager.getAppUpdateInfo().addOnSuccessListener(info -> {
                        try {
                            boolean available = info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE
                                    || info.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS;
                            if (!available || !manager.startUpdateFlowForResult(info, launcher,
                                    AppUpdateOptions.newBuilder(AppUpdateType.IMMEDIATE).build())) {
                                finishUpdate(false);
                            }
                        } catch (Exception error) {
                            finishUpdate(false);
                        }
                    }).addOnFailureListener(error -> finishUpdate(false));
                    break;
                case "openStore":
                    try {
                        activity.startActivity(new Intent(Intent.ACTION_VIEW,
                                Uri.parse("market://details?id=" + activity.getPackageName())));
                        result.success(null);
                    } catch (ActivityNotFoundException missingStore) {
                        try {
                            activity.startActivity(new Intent(Intent.ACTION_VIEW,
                                    Uri.parse("https://play.google.com/store/apps/details?id=" + activity.getPackageName())));
                            result.success(null);
                        } catch (ActivityNotFoundException missingBrowser) {
                            result.error("STORE_UNAVAILABLE", "Não foi possível abrir a Play Store.", null);
                        }
                    }
                    break;
                default:
                    result.notImplemented();
            }
        });
    }

    @SuppressWarnings("deprecation")
    private void installation(MethodChannel.Result result) {
        try {
            PackageManager packages = activity.getPackageManager();
            PackageInfo info = packages.getPackageInfo(activity.getPackageName(), 0);
            String installer = Build.VERSION.SDK_INT >= 30
                    ? packages.getInstallSourceInfo(activity.getPackageName()).getInstallingPackageName()
                    : packages.getInstallerPackageName(activity.getPackageName());
            Map<String, Object> values = new HashMap<>();
            values.put("versionCode", Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode);
            values.put("playStore", !BuildConfig.DEBUG && "com.android.vending".equals(installer));
            result.success(values);
        } catch (Exception error) {
            result.error("INSTALLATION_UNKNOWN", "Instalação indisponível.", null);
        }
    }

    private void finishUpdate(boolean success) {
        MethodChannel.Result pending = pendingUpdate;
        pendingUpdate = null;
        if (pending != null) pending.success(success);
    }

    void dispose() {
        channel.setMethodCallHandler(null);
        finishUpdate(false);
        launcher.unregister();
    }
}
