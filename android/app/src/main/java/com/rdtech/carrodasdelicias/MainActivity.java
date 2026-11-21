package com.rdtech.carrodasdelicias;

import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.android.RenderMode;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterFragmentActivity {
    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
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
    public RenderMode getRenderMode() {
        return RenderMode.texture;
    }
}
