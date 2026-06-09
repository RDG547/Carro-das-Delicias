package com.rdtech.carrodasdelicias;

import android.os.Bundle;
import androidx.activity.EdgeToEdge;
import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.android.RenderMode;

public class MainActivity extends FlutterFragmentActivity {
    @Override
    public RenderMode getRenderMode() {
        return RenderMode.texture;
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        EdgeToEdge.enable(this);
        super.onCreate(savedInstanceState);
    }
}
