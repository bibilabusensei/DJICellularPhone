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
    static final int VENDOR = 0x2CA3;
    static final int PRODUCT = 0x4009;
    private final UsbDeviceConnection connection;
    private final UsbInterface control;
    private final UsbEndpoint input;
    private final UsbEndpoint output;
    private volatile boolean closed;

    UsbBulkTransport(UsbManager manager, UsbDevice device) throws IOException {
        if (device.getVendorId() != VENDOR || device.getProductId() != PRODUCT ||
                device.getInterfaceCount() != 5 || !manager.hasPermission(device)) {
            throw new IOException("目标或 USB 权限不符；只允许 2CA3:4009 的原有五接口配置。");
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
        UsbDeviceConnection opened = manager.openDevice(device);
        if (opened == null) throw new IOException("无法打开设备；不重装驱动。");
        if (!opened.claimInterface(found, false)) {
            opened.close();
            throw new IOException("控制接口被占用；不强制抢占系统驱动。");
        }
        connection = opened;
        control = found;
        input = read;
        output = write;
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
