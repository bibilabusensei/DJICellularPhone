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
            Toast.makeText(context, "USB 未获授权或目标不符，未打开模块。", Toast.LENGTH_LONG).show();
            return;
        }
        Intent connect = new Intent(context, ModemService.class).setAction(ModemService.CONNECT)
                .putExtra(UsbManager.EXTRA_DEVICE, device);
        try {
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(connect);
            else context.startService(connect);
        } catch (RuntimeException failure) {
            Toast.makeText(context, "请保持应用在前台并重新连接。", Toast.LENGTH_LONG).show();
        }
    }
}
