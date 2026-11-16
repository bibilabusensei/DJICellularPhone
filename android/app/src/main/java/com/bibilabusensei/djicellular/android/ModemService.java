package com.bibilabusensei.djicellular.android;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.os.Binder;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.os.SystemClock;
import android.telephony.SmsMessage;
import com.bibilabusensei.djicellular.android.core.AtClient;
import com.bibilabusensei.djicellular.android.core.SmsSubmit;
import com.bibilabusensei.djicellular.android.core.VoiceCall;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

public final class ModemService extends Service {
    public static final String CONNECT = "com.bibilabusensei.djicellular.CONNECT";
    private static final String CHANNEL = "modem-session";
    private final ScheduledExecutorService worker = Executors.newSingleThreadScheduledExecutor();
    private final LocalBinder binder = new LocalBinder();
    private final Set<String> seenMessages = Collections.synchronizedSet(new HashSet<>());
    private volatile AtClient client;
    private volatile String deviceName;
    private volatile boolean polling;
    private volatile boolean ready;
    private volatile boolean busy;
    private volatile int generation;
    private volatile long homeRegistrationAt;
    private volatile String connectionStage = "idle";
    private volatile String status = "等待手动连接；请先查看上方系统 USB 列表。这不是探测失败结论。";
    private volatile String messages = "未读取短信";
    private volatile String callState = "未读取呼叫；没有双向语音驱动。";
    private volatile String event = "无业务操作";
    private boolean incomingPreviously;
    private PowerManager.WakeLock wakeLock;

    public final class LocalBinder extends Binder {
        ModemService service() { return ModemService.this; }
    }

    private final BroadcastReceiver detachReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            UsbDevice detached = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
            if (detached != null && detached.getDeviceName().equals(deviceName)) disconnect();
        }
    };

    @Override public void onCreate() {
        super.onCreate();
        IntentFilter filter = new IntentFilter(UsbManager.ACTION_USB_DEVICE_DETACHED);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(detachReceiver, filter, Context.RECEIVER_EXPORTED);
        else registerReceiver(detachReceiver, filter);
        PowerManager power = (PowerManager) getSystemService(POWER_SERVICE);
        if (power != null) {
            wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "DJICellular:explicit-monitor");
            wakeLock.setReferenceCounted(false);
        }
        worker.scheduleWithFixedDelay(() -> {
            if (!polling || !ready || busy) return;
            if (wakeLock != null) wakeLock.acquire(600000L);
            if (!polling || !ready) { releaseWakeLock(); return; }
            perform(() -> {
                updateCalls();
                updateMessages();
            });
            if (!polling) releaseWakeLock();
        }, 5, 5, TimeUnit.SECONDS);
    }

    @Override public IBinder onBind(Intent intent) { return binder; }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null || !CONNECT.equals(intent.getAction())) return START_NOT_STICKY;
        UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
        UsbManager manager = (UsbManager) getSystemService(USB_SERVICE);
        if (device == null || manager == null || !manager.hasPermission(device) ||
                device.getVendorId() != UsbBulkTransport.VENDOR || device.getProductId() != UsbBulkTransport.PRODUCT) {
            ConnectionStatus.publish("usb_permission_lost", "连接服务没有有效的目标 USB 授权；未打开控制口。" );
            stopSelf();
            return START_NOT_STICKY;
        }
        try {
            startForeground(1, notification("USB 会话开启；退出界面不会自动断开。"));
        } catch (RuntimeException failure) {
            event = "无法启动 USB 前台服务，请确认授权后在应用前台重试。";
            ConnectionStatus.publish("foreground_service_failed", event);
            stopSelf();
            return START_NOT_STICKY;
        }
        if (client == null && !busy) {
            busy = true;
            int expectedGeneration = ++generation;
            worker.execute(() -> {
                try {
                    progress("connect_preflight", "连接服务已启动，核对当前设备是否仍在。" );
                    UsbDevice current = manager.getDeviceList().get(device.getDeviceName());
                    if (current == null || current.getDeviceId() != device.getDeviceId()) {
                        throw new IllegalStateException("设备已改变，请重新授权。");
                    }
                    if (expectedGeneration != generation) throw new IllegalStateException("连接已取消。");
                    AtClient opened = new AtClient(new UsbBulkTransport(manager, current, this::progress));
                    synchronized (ModemService.this) {
                        if (expectedGeneration != generation) {
                            opened.close();
                            throw new IllegalStateException("连接已取消。");
                        }
                        client = opened;
                        deviceName = current.getDeviceName();
                    }
                    progress("at_handshake", "USB 控制口已打开，发送一次 AT 握手；超时即停止，不猜初始化命令。" );
                    opened.query("AT");
                    progress("usb_mode_query", "AT 已实际应答，正在只读确认原有 USB 模式。" );
                    boolean mode30 = false;
                    for (String line : opened.query("AT+GTUSBMODE?")) mode30 |= line.matches("\\+GTUSBMODE:\\s*30");
                    if (!mode30) throw new IllegalStateException("未确认模式 30；停止，不修改模式。");
                    progress("sim_query", "已确认模式 30，正在读取 SIM 和注册状态。" );
                    String sim = opened.query("AT+CPIN?").toString().contains("READY") ? "SIM READY" : "SIM 状态未就绪";
                    recordRegistration(opened.query("AT+CEREG?"));
                    if (expectedGeneration != generation) throw new IllegalStateException("连接已取消。");
                    ready = true;
                    status = "已取得实际 AT 应答，模式 30，" + sim + "。这不证明语音或数据通路可用。";
                    event = "已连接；未改 USB 配置、DTR/RTS、APN 或固件。";
                    progress("at_ready", status);
                } catch (Exception failure) {
                    event = safeError(failure);
                    ConnectionStatus.publish("failed_at_" + connectionStage, event);
                    closeClient();
                    status = "连接未通过；未尝试厂商初始化、其他接口或驱动抢占。";
                    stopForeground(true);
                    stopSelf();
                } finally {
                    busy = false;
                }
            });
        }
        return START_NOT_STICKY;
    }

    private interface Operation { void run() throws Exception; }

    private void progress(String stage, String message) {
        connectionStage = stage;
        ConnectionStatus.publish(stage, message);
    }

    private void perform(Operation operation) {
        if (!ready || client == null) { event = "请先连接模块并通过 AT 握手。"; return; }
        busy = true;
        try { operation.run(); }
        catch (Exception failure) {
            event = safeError(failure);
            polling = false;
            releaseWakeLock();
            AtClient opened = client;
            if (opened != null && !opened.isUsable()) {
                closeClient();
                status = "会话异常，已释放 USB，不自动重连。";
                stopForeground(true);
                stopSelf();
            }
        } finally { busy = false; }
    }

    private String safeError(Exception failure) {
        if (failure.getMessage() == null) return "操作失败，未自动重试。";
        return failure.getMessage().replaceAll("/dev/[^\\s,;\\]\\)]+", "[设备路径已省略]")
                .replaceAll("\\b[0-9]{7,22}\\b", "[编号已省略]");
    }

    private synchronized void enqueue(Operation operation) {
        if (!ready || busy || client == null) { event = "会话未就绪或正在处理，请勿重复提交。"; return; }
        AtClient expected = client;
        busy = true;
        worker.execute(() -> {
            if (client == expected && ready) perform(operation);
            busy = false;
        });
    }

    public void readSms() { enqueue(this::updateMessages); }
    public void refreshCalls() { enqueue(this::updateCalls); }
    public void refreshRegistration() { enqueue(() -> {
        recordRegistration(client.query("AT+CEREG?"));
        event = isHomeRegisteredRecently() ? "本地 EPS 注册已确认，5 分钟内可单独测试系统以太网。" : "未确认本地注册，不进行流量测试。";
    }); }

    private void recordRegistration(List<String> lines) {
        homeRegistrationAt = 0;
        for (String line : lines) {
            if (line.matches("\\+CEREG:\\s*\\d+,\\s*1(?:,.*)?")) homeRegistrationAt = SystemClock.elapsedRealtime();
        }
    }

    public boolean isHomeRegisteredRecently() {
        return ready && homeRegistrationAt > 0 && SystemClock.elapsedRealtime() - homeRegistrationAt < 300000L;
    }

    public void sendSms(String recipient, String text) {
        SmsSubmit submit = new SmsSubmit(recipient, text);
        enqueue(() -> {
            client.sendSms(submit);
            event = "模块已接受短信提交；不是送达回执，没有自动重试。";
        });
    }

    public void voice(String action, String number, boolean acknowledged) {
        if (!acknowledged) { event = "呼叫实验未授权。"; return; }
        enqueue(() -> {
            client.voiceAction(action, number);
            event = "模块已接受呼叫控制命令；本 App 没有接入通话声音。";
            updateCalls();
        });
    }

    public void setPolling(boolean enabled) {
        polling = enabled && ready;
        if (!polling) releaseWakeLock();
        event = polling ? "已开启前台服务监听；每 5 秒查询，屏幕关闭后的可靠性需 GSI 真机验证。" : "已关闭监听。";
    }

    private void updateCalls() throws Exception {
        AtClient selected = client;
        if (selected == null) return;
        List<VoiceCall> calls = VoiceCall.parse(selected.query("AT+CLCC"));
        if (client != selected) return;
        int voices = 0;
        int data = 0;
        boolean incoming = false;
        StringBuilder details = new StringBuilder();
        for (VoiceCall call : calls) {
            if (call.mode == 0) {
                voices++;
                incoming |= call.state == 4 || call.state == 5;
                details.append("语音状态 ").append(call.state).append("（0活动/1保持/2拨出/3回铃/4来电/5等待）\n");
            } else data++;
        }
        callState = "语音记录 " + voices + "，数据/未知记录 " + data + "。\n" + details +
                "数据记录不是通话；存在数据/未知记录时禁止呼叫控制。";
        if (incoming && !incomingPreviously) notifyEvent("检测到模块来电；语音音频未接入，不能当作可用电话。");
        incomingPreviously = incoming;
    }

    private void updateMessages() throws Exception {
        AtClient selected = client;
        if (selected == null) return;
        List<String> lines = selected.readMessages();
        if (client != selected) return;
        StringBuilder display = new StringBuilder();
        Set<String> current = new HashSet<>();
        boolean newMessage = false;
        for (int position = 0; position < lines.size(); position++) {
            String header = lines.get(position);
            if (!header.startsWith("+CMGL:") || position + 1 >= lines.size()) continue;
            String pdu = lines.get(++position);
            byte[] bytes = SmsSubmit.decodeHex(pdu);
            SmsMessage message = Build.VERSION.SDK_INT >= 23 ? SmsMessage.createFromPdu(bytes, "3gpp") : SmsMessage.createFromPdu(bytes);
            if (message == null) {
                display.append("存储记录无法解码；未删除或更改格式。\n");
            } else {
                display.append(message.getOriginatingAddress()).append("\n").append(message.getMessageBody()).append("\n\n");
            }
            current.add(pdu);
            newMessage |= !seenMessages.contains(pdu);
        }
        synchronized (this) {
            if (client != selected || !ready) return;
            seenMessages.retainAll(current);
            seenMessages.addAll(current);
            messages = display.length() == 0 ? "模块当前存储未返回短信；未切存储区，不代表收信能力已验证。" : display.toString();
            if (newMessage && polling) notifyEvent("模块存储出现新短信；内容只在应用内显示。");
            event = "已读取模块当前存储；未删除短信，读取可能将未读记录标为已读。";
        }
    }

    private Notification notification(String text) {
        NotificationManager manager = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= 26 && manager != null) {
            manager.createNotificationChannel(new NotificationChannel(CHANNEL, "模块 USB 会话与提示", NotificationManager.IMPORTANCE_DEFAULT));
        }
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(this, CHANNEL) : new Notification.Builder(this);
        int immutable = Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0;
        PendingIntent open = PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class), PendingIntent.FLAG_UPDATE_CURRENT | immutable);
        return builder.setSmallIcon(R.drawable.ic_usb).setContentTitle("DJI 模块研究")
                .setContentText(text).setContentIntent(open).setOngoing(true).build();
    }

    private void notifyEvent(String text) {
        NotificationManager manager = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (manager != null && (Build.VERSION.SDK_INT < 33 || checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED)) manager.notify(1, notification(text));
    }

    public boolean isReady() { return ready && !busy; }
    public boolean isPolling() { return polling; }
    public String status() { return status; }
    public String smsText() { return messages; }
    public String callsText() { return callState; }
    public String eventText() { return event; }
    public String diagnosticReport() {
        return "Android " + Build.VERSION.RELEASE + " / API " + Build.VERSION.SDK_INT +
                "\nUSB AT ready: " + ready + "\nPolling: " + polling +
                "\nDevice: 2CA3:4009 / MI_02 only\nAudio implemented: false\nModem data driver: false" +
                "\nHardware validation: pending\n" + status + "\n" + event + "\n" + ConnectionStatus.report() +
                "\n不含短信正文、号码、SIM 标识、设备序列号或 IP；不要把诊断报告当作全功能验收。";
    }

    private void releaseWakeLock() { if (wakeLock != null && wakeLock.isHeld()) wakeLock.release(); }

    private synchronized void closeClient() {
        ready = false;
        homeRegistrationAt = 0;
        polling = false;
        releaseWakeLock();
        AtClient opened = client;
        client = null;
        if (opened != null) try { opened.close(); } catch (Exception ignored) { }
        deviceName = null;
    }

    public synchronized void disconnect() {
        generation++;
        closeClient();
        messages = "会话关闭，短信显示已清除。";
        seenMessages.clear();
        status = "已断开；未发送挂断、复位或改模式命令。已有呼叫不会自动结束。";
        ConnectionStatus.publish("disconnected", status);
        stopForeground(true);
        stopSelf();
    }

    @Override public void onDestroy() {
        closeClient();
        worker.shutdownNow();
        unregisterReceiver(detachReceiver);
        super.onDestroy();
    }
}
