package com.bibilabusensei.djicellular.android;

import android.content.Context;
import android.content.pm.PackageManager;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbEndpoint;
import android.hardware.usb.UsbInterface;
import android.hardware.usb.UsbManager;
import android.os.Build;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;

final class UsbInventory {
    final UsbManager manager;
    final List<UsbDevice> targets = new ArrayList<>();
    final String stage;
    final String summary;
    final String details;

    UsbInventory(Context context) {
        boolean host = context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_USB_HOST);
        manager = (UsbManager) context.getSystemService(Context.USB_SERVICE);
        StringBuilder report = new StringBuilder("App 0.1.1 / Android ").append(Build.VERSION.RELEASE)
                .append(" / API ").append(Build.VERSION.SDK_INT)
                .append("\n型号: ").append(Build.MANUFACTURER).append(' ').append(Build.MODEL)
                .append("\n系统声明 USB Host: ").append(host ? "是" : "否")
                .append("\nUsbManager 服务: ").append(manager != null ? "有" : "无");
        if (manager == null) {
            stage = "usb_service_missing";
            summary = "系统没有向 App 提供 USB 服务；未打开设备。";
            details = report.toString();
            return;
        }
        List<UsbDevice> devices;
        try {
            devices = new ArrayList<>(manager.getDeviceList().values());
            Collections.sort(devices, new Comparator<UsbDevice>() {
                @Override public int compare(UsbDevice first, UsbDevice second) {
                    int vendor = Integer.compare(first.getVendorId(), second.getVendorId());
                    return vendor != 0 ? vendor : Integer.compare(first.getProductId(), second.getProductId());
                }
            });
        } catch (RuntimeException failure) {
            stage = "usb_list_unavailable";
            summary = "USB 列表读取失败（" + failure.getClass().getSimpleName() + "），不能当作模块未插入。";
            details = report.toString();
            return;
        }
        report.append("\n系统 USB 设备数量: ").append(devices.size());
        for (UsbDevice device : devices) {
            boolean target = device.getVendorId() == UsbBulkTransport.VENDOR && device.getProductId() == UsbBulkTransport.PRODUCT;
            if (target) targets.add(device);
            report.append("\n\nVID:PID ").append(hex(device.getVendorId(), 4)).append(':')
                    .append(hex(device.getProductId(), 4)).append(target ? " [目标]" : " [仅列出，不访问]")
                    .append("\n接口条目: ").append(device.getInterfaceCount())
                    .append(" / 已有 USB 授权: ").append(permissionLabel(device));
            for (int position = 0; position < device.getInterfaceCount(); position++) {
                UsbInterface usbInterface = device.getInterface(position);
                report.append("\n  接口 ").append(usbInterface.getId()).append(" alt ")
                        .append(usbInterface.getAlternateSetting()).append(" 类 ")
                        .append(hex(usbInterface.getInterfaceClass(), 2)).append('/')
                        .append(hex(usbInterface.getInterfaceSubclass(), 2)).append('/')
                        .append(hex(usbInterface.getInterfaceProtocol(), 2));
                for (int endpointIndex = 0; endpointIndex < usbInterface.getEndpointCount(); endpointIndex++) {
                    UsbEndpoint endpoint = usbInterface.getEndpoint(endpointIndex);
                    report.append(" ep=").append(hex(endpoint.getAddress(), 2))
                            .append("(type ").append(endpoint.getType()).append(')');
                }
            }
        }
        if (devices.isEmpty()) {
            stage = "no_usb_devices";
            summary = host ? "系统 USB 列表为 0；尚未进入授权或 AT 阶段。请核对 OTG 主机角色、数据线、供电和 ROM USB 支持。" :
                    "系统未声明 USB Host，且 USB 列表为 0；可能是 GSI/厂商 USB 支持或连接问题，不是短信权限问题。";
        } else if (targets.isEmpty()) {
            stage = "target_not_listed";
            summary = "系统看到了 USB 设备，但没有 2CA3:4009。请分享下面的列表；不会猜测或访问其他设备。";
        } else if (targets.size() > 1) {
            stage = "multiple_targets";
            summary = "系统看到了多个目标模块；为避免打开错误设备，暂不连接。";
        } else {
            stage = "target_visible";
            summary = "系统已看到 2CA3:4009；点击下一步请求授权并尝试 AT 握手。设备出现不等于通信已成功。";
        }
        details = report.toString();
    }

    private static String hex(int value, int width) {
        return String.format(Locale.ROOT, width == 4 ? "%04X" : "%02X", value);
    }

    private String permissionLabel(UsbDevice device) {
        try { return manager.hasPermission(device) ? "是" : "否"; }
        catch (RuntimeException failure) { return "读取失败"; }
    }
}
