package com.rdtech.carrodasdelicias;

import android.os.Bundle;
import androidx.activity.EdgeToEdge;
import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.android.RenderMode;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterFragmentActivity {
    private PlayUpdateBridge updateBridge;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        EdgeToEdge.enable(this);
        super.onCreate(savedInstanceState);
    }

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        updateBridge = new PlayUpdateBridge(this, flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(),
                "com.rdtech.carrodasdelicias/config").setMethodCallHandler((call, result) -> {
            if (call.method.equals("getMapboxAccessToken")) {
                result.success(getString(R.string.mapbox_access_token));
            } else {
                result.notImplemented();
            }
        });
    }

    @Override
    public void cleanUpFlutterEngine(FlutterEngine flutterEngine) {
        if (updateBridge != null) updateBridge.dispose();
        super.cleanUpFlutterEngine(flutterEngine);
    }
    @Override
    public RenderMode getRenderMode() {
        return RenderMode.texture;
    }
}
