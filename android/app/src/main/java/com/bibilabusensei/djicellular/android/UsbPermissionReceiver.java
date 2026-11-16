package com.bibilabusensei.djicellular.android;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.os.Build;
import android.widget.Toast;

public final class UsbPermissionReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
        UsbManager manager = (UsbManager) context.getSystemService(Context.USB_SERVICE);
        if (!intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false) || device == null ||
                manager == null || !manager.hasPermission(device) ||
                device.getVendorId() != UsbBulkTransport.VENDOR || device.getProductId() != UsbBulkTransport.PRODUCT) {
            ConnectionStatus.publish("usb_permission_denied", "USB 未获授权、已断开或目标不符；没有打开设备。" );
            Toast.makeText(context, ConnectionStatus.message(), Toast.LENGTH_LONG).show();
            return;
        }
        ConnectionStatus.publish("usb_permission_granted", "安卓已授予目标 USB 访问权限，准备启动连接服务。" );
        startConnection(context, device);
    }

    static void startConnection(Context context, UsbDevice device) {
        Intent connect = new Intent(context, ModemService.class).setAction(ModemService.CONNECT)
                .putExtra(UsbManager.EXTRA_DEVICE, device);
        try {
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(connect);
            else context.startService(connect);
        } catch (RuntimeException failure) {
            ConnectionStatus.publish("usb_service_start_failed", "USB 已授权，但连接服务启动失败（" + failure.getClass().getSimpleName() + "）。请保持 App 在前台。" );
            Toast.makeText(context, ConnectionStatus.message(), Toast.LENGTH_LONG).show();
        }
    }
}
