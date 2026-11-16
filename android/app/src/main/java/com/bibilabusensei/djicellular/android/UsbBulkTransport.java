package com.bibilabusensei.djicellular.android;

import android.hardware.usb.UsbConstants;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbEndpoint;
import android.hardware.usb.UsbInterface;
import android.hardware.usb.UsbManager;
import com.bibilabusensei.djicellular.android.core.AtTransport;
import java.io.IOException;

final class UsbBulkTransport implements AtTransport {
    interface StageListener { void report(String stage, String message); }
    static final int VENDOR = 0x2CA3;
    static final int PRODUCT = 0x4009;
    private final UsbDeviceConnection connection;
    private final UsbInterface control;
    private final UsbEndpoint input;
    private final UsbEndpoint output;
    private volatile boolean closed;

    UsbBulkTransport(UsbManager manager, UsbDevice device, StageListener listener) throws IOException {
        listener.report("usb_validate", "核对目标身份、授权和控制接口，不修改配置。" );
        if (device.getVendorId() != VENDOR || device.getProductId() != PRODUCT ||
                !manager.hasPermission(device)) {
            throw new IOException("目标或 USB 权限不符；只允许 2CA3:4009。");
        }
        UsbInterface found = null;
        for (int position = 0; position < device.getInterfaceCount(); position++) {
            UsbInterface candidate = device.getInterface(position);
            if (candidate.getId() == 2 && candidate.getAlternateSetting() == 0) {
                if (found != null) throw new IOException("控制接口不唯一");
                found = candidate;
            }
        }
        if (found == null || found.getInterfaceClass() != 255 || found.getInterfaceSubclass() != 0 ||
                found.getInterfaceProtocol() != 0) throw new IOException("MI_02 描述符不符合已知快照。");
        UsbEndpoint read = null;
        UsbEndpoint write = null;
        for (int position = 0; position < found.getEndpointCount(); position++) {
            UsbEndpoint endpoint = found.getEndpoint(position);
            if (endpoint.getType() != UsbConstants.USB_ENDPOINT_XFER_BULK) continue;
            if (endpoint.getAddress() == 0x84) read = endpoint;
            if (endpoint.getAddress() == 0x03) write = endpoint;
        }
        if (read == null || write == null) throw new IOException("控制端点与已知快照不符。");
        listener.report("usb_open", "已核对 MI_02 与端点 84/03，正在打开目标 USB 设备。" );
        UsbDeviceConnection opened = manager.openDevice(device);
        if (opened == null) throw new IOException("无法打开设备；不重装驱动。");
        listener.report("usb_claim", "USB 已打开，尝试非强制占用控制接口，不碰网卡接口。" );
        if (!opened.claimInterface(found, false)) {
            opened.close();
            throw new IOException("控制接口被占用；不强制抢占系统驱动。");
        }
        connection = opened;
        control = found;
        input = read;
        output = write;
        listener.report("usb_claimed", "控制接口已打开，尚未验证 AT 应答。" );
    }

    @Override public void write(byte[] data) throws IOException {
        if (closed) throw new IOException("USB 已关闭");
        int offset = 0;
        while (offset < data.length) {
            int count = connection.bulkTransfer(output, data, offset, data.length - offset, 1000);
            if (count <= 0) throw new IOException("USB 写入未完成，不自动重试操作。");
            offset += count;
        }
    }

    @Override public int read(byte[] buffer, int timeoutMillis) throws IOException {
        if (closed) throw new IOException("USB 已关闭");
        int count = connection.bulkTransfer(input, buffer, buffer.length, timeoutMillis);
        return Math.max(0, count);
    }

    @Override public void close() {
        if (closed) return;
        closed = true;
        connection.releaseInterface(control);
        connection.close();
    }
}
