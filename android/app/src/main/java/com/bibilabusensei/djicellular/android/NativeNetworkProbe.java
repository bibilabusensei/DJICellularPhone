package com.bibilabusensei.djicellular.android;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;
import javax.net.ssl.HttpsURLConnection;

final class NativeNetworkProbe {
    private final ConnectivityManager manager;

    NativeNetworkProbe(Context context) {
        manager = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
    }

    List<Network> candidates() {
        List<Network> result = new ArrayList<>();
        if (manager == null) return result;
        for (Network network : manager.getAllNetworks()) {
            if (isEthernet(network)) result.add(network);
        }
        return result;
    }

    private boolean isEthernet(Network network) {
        NetworkCapabilities capabilities = manager.getNetworkCapabilities(network);
        return capabilities != null && capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) &&
                !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
                !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) &&
                !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN);
    }

    String run(Network network) {
        HttpsURLConnection connection = null;
        try {
            if (!isEthernet(network)) return "所选网络已消失，不回退其他网络。";
            connection = (HttpsURLConnection) network.openConnection(new URL("https://example.com/"));
            connection.setConnectTimeout(8000);
            connection.setReadTimeout(8000);
            connection.setInstanceFollowRedirects(false);
            connection.setRequestMethod("HEAD");
            connection.setUseCaches(false);
            int response = connection.getResponseCode();
            if (!isEthernet(network)) return "请求后无法确认所选以太网，未宣称成功。";
            return response >= 200 && response < 300 ? "所选系统以太网 HTTPS 成功；尚未证明它属于 IG831T 或来自模块 SIM。" :
                    "收到 HTTP " + response + "；不跟随重定向，不宣称模块上网成功。";
        } catch (Exception failure) {
            return "有线 HTTPS 未通过（" + failure.getClass().getSimpleName() + "）；未回退 Wi-Fi 或平板内置蜂窝。";
        } finally {
            if (connection != null) connection.disconnect();
        }
    }
}
