package com.bibilabusensei.djicellular.android;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.PendingIntent;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.content.pm.PackageManager;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.net.Network;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.text.InputFilter;
import android.text.InputType;
import android.view.View;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import com.bibilabusensei.djicellular.android.core.SmsSubmit;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final ExecutorService networkWorker = Executors.newSingleThreadExecutor();
    private ModemService service;
    private LinearLayout content;
    private TextView sessionStatus;
    private TextView events;
    private TextView connectionMessages;
    private TextView inventoryView;
    private UsbInventory inventory;
    private TextView smsView;
    private TextView callsView;
    private TextView networkView;
    private EditText recipient;
    private EditText body;
    private EditText number;
    private CheckBox experimentalCalls;
    private CheckBox polling;
    private boolean rendering;
    private boolean bound;
    private boolean networkBusy;
    private final List<Button> businessButtons = new ArrayList<>();

    private final ServiceConnection binding = new ServiceConnection() {
        @Override public void onServiceConnected(ComponentName name, IBinder binder) {
            service = ((ModemService.LocalBinder) binder).service();
            render();
        }
        @Override public void onServiceDisconnected(ComponentName name) { service = null; render(); }
    };

    private final Runnable refresh = new Runnable() {
        @Override public void run() { render(); handler.postDelayed(this, 1000); }
    };

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        ScrollView scroll = new ScrollView(this);
        content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        int padding = dp(18);
        content.setPadding(padding, padding, padding, padding);
        content.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(padding, padding + insets.getSystemWindowInsetTop(), padding,
                    padding + insets.getSystemWindowInsetBottom());
            return insets;
        });
        scroll.addView(content);
        setContentView(scroll);
        heading("DJI 模块 · 安卓兼容实验版");
        text("支持安装目标：安卓 5+，包含安卓 10/11。需要 USB Host/OTG 和足够供电；GSI 系统与真实模块兼容性尚未验证。不是已完成的电话或系统蜂窝驱动。");
        text("直接使用模块 USB，不用平板内置 SIM，不需要短信/电话权限。没有通话音频，也不会切 USB 模式、刷固件、改 APN、强占网卡或运行 root 命令。");
        sessionStatus = text("未连接");
        events = text("无业务操作");
        heading("第一步：系统是否看到 USB（无需授权）");
        inventoryView = text("尚未读取系统 USB 列表");
        inventoryView.setTextIsSelectable(true);
        button("只读刷新 USB 设备列表", () -> refreshInventory(true));
        heading("第二步：授权与连接进度");
        connectionMessages = text(ConnectionStatus.message());
        connectionMessages.setTextIsSelectable(true);
        button("连接模块并查询状态（首次会申请 USB 授权）", this::requestUsb);
        button("释放 USB / 关闭会话（不会自动挂断已有电话）", () -> { if (service != null) service.disconnect(); });
        button("通知权限（安卓 13+）", () -> {
            if (Build.VERSION.SDK_INT >= 33) requestPermissions(new String[] {android.Manifest.permission.POST_NOTIFICATIONS}, 9);
            else message("本系统不需要单独申请通知权限。");
        });
        polling = new CheckBox(this);
        polling.setText("监听来电/短信（读取可标已读，保持 CPU 唤醒，会耗电）");
        polling.setOnCheckedChangeListener((view, checked) -> {
            if (!rendering && service != null) service.setPolling(checked);
        });
        content.addView(polling);
        text("监听默认关闭，每 5 秒查询；ROM 休眠限制和模块原有收信设置仍可能影响及时性。退出界面不会自动结束已确认的 USB 会话，通知会持续显示。");

        heading("短信 · 通过外置模块");
        recipient = input("收件号码，例如 +86…", InputType.TYPE_CLASS_PHONE);
        body = input("单条短信正文（最多 70 个 UCS-2 字符，不支持 emoji/拆分）", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        body.setFilters(new InputFilter[] {new InputFilter.LengthFilter(70)});
        businessButton("发送短信（可能收费）", () -> {
            try {
                String destination = recipient.getText().toString().trim();
                String messageBody = body.getText().toString();
                new SmsSubmit(destination, messageBody);
                confirm("确认通过模块 SIM 发送？", "可能收费；模块确认不等于送达。超时不要重复发送。", () -> {
                    if (service != null) service.sendSms(destination, messageBody);
                });
            } catch (IllegalArgumentException failure) { message(failure.getMessage()); }
        });
        businessButton("读取模块短信（可能标为已读，不删除）", () -> confirm("允许读取模块当前存储？", "标准 CMGL 读取可能将未读短信标为已读，不删除记录，也不修改短信格式或存储区。", () -> {
            if (service != null) service.readSms();
        }));
        text("只接受模块已处于 PDU 模式。不是 PDU 模式时停止，不自动修改短信格式、存储区或 CNMI 设置。短信仅存在内存中；系统/模块仍决定是否收到新短信。");
        smsView = text("未读取短信");
        smsView.setTextIsSelectable(true);

        heading("来电与呼叫控制实验 · 没有双向声音");
        text("这不是可正常对话的电话。没有麦克风/听筒数据通道，不用于紧急呼叫。存在数据/未知呼叫或未确认专用挂断命令时，所有呼叫操作会被拒绝，避免中断数据。");
        experimentalCalls = new CheckBox(this);
        experimentalCalls.setText("我明白没有通话声音，仍允许收费呼叫控制实验");
        content.addView(experimentalCalls);
        number = input("实验电话号码", InputType.TYPE_CLASS_PHONE);
        businessButton("读取呼叫状态（不会拨号）", () -> { if (service != null) service.refreshCalls(); });
        businessButton("实验：拨出", () -> call("dial"));
        businessButton("实验：接听", () -> call("answer"));
        businessButton("实验：挂断语音", () -> call("hangup"));
        callsView = text("未读取呼叫状态");

        heading("数据流量 · 仅使用系统已有有线网络");
        text("普通 USB 权限不能自动创建 Android 蜂窝网卡。若 GSI 内核没有此模块的网络驱动，App 不会用 Wi-Fi 冒充模块联网，也不会替换内核或抢占 MI_04。当前没有用户态 QMI 数据驱动/VPN 实现。");
        button("查看系统以太网并确认小流量 HTTPS 测试", this::networkTest);
        networkView = text("未测试网络");
        businessButton("刷新模块本地注册（不选网、不启动数据）", () -> { if (service != null) service.refreshRegistration(); });
        heading("分享诊断（不含短信和号码）");
        button("分享兼容性报告", () -> {
            UsbInventory current = refreshInventory(false);
            String report = current.summary + "\n" + current.details + "\n\n" + ConnectionStatus.report() + "\n\n" +
                    (service == null ? "未绑定模块会话，未完成硬件测试。" : service.diagnosticReport());
            Intent share = new Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT,
                    report);
            startActivity(Intent.createChooser(share, "分享诊断，不含短信/号码"));
        });
        refreshInventory(false);
    }

    private UsbInventory refreshInventory(boolean announce) {
        inventory = new UsbInventory(this);
        inventoryView.setText(inventory.summary + "\n\n" + inventory.details);
        if (announce) ConnectionStatus.publish(inventory.stage, inventory.summary);
        return inventory;
    }

    private void requestUsb() {
        UsbInventory current = refreshInventory(true);
        if (current.manager == null || current.targets.size() != 1) return;
        UsbManager manager = current.manager;
        UsbDevice device = current.targets.get(0);
        confirm("允许连接模块控制接口？", "只使用 MI_02，不强制抢占驱动，不碰网卡接口。将发送 AT 和已验证的状态查询；无应答就停止。供电安全需你事先确认。", () -> {
            try {
                if (manager.hasPermission(device)) {
                    ConnectionStatus.publish("usb_permission_cached", "已有目标 USB 授权，不会再次弹出授权框。准备连接控制口。" );
                    UsbPermissionReceiver.startConnection(this, device);
                } else {
                    ConnectionStatus.publish("usb_permission_requested", "已请求安卓 USB 授权，等待系统对话框；尚未打开设备。" );
                    Intent permission = new Intent(this, UsbPermissionReceiver.class).setAction("com.bibilabusensei.djicellular.USB_PERMISSION");
                    int mutable = Build.VERSION.SDK_INT >= 31 ? PendingIntent.FLAG_MUTABLE : 0;
                    manager.requestPermission(device, PendingIntent.getBroadcast(this, 1, permission, PendingIntent.FLAG_UPDATE_CURRENT | mutable));
                }
            } catch (RuntimeException failure) {
                ConnectionStatus.publish("usb_permission_request_failed", "USB 授权请求失败（" + failure.getClass().getSimpleName() + "）；没有打开设备。" );
            }
        });
    }

    private void call(String action) {
        if (!experimentalCalls.isChecked()) { message("请先阅读并明确允许无声音的呼叫控制实验。"); return; }
        confirm("仅实验呼叫控制", "可能真实接通并产生费用，但本 App 没有双向语音。断开 USB 不会自动挂断。确定继续？", () -> {
            if (service != null) service.voice(action, number.getText().toString().trim(), experimentalCalls.isChecked());
        });
    }

    private void networkTest() {
        if (networkBusy) { message("网络测试正在进行，不重复提交。"); return; }
        if (service == null || !service.isHomeRegisteredRecently()) {
            networkView.setText("需先通过模块 AT 连接并刷新本地 EPS 注册；拒绝漫游或超过 5 分钟的旧状态。");
            return;
        }
        NativeNetworkProbe probe = new NativeNetworkProbe(this);
        List<Network> networks = probe.candidates();
        if (networks.isEmpty()) {
            networkView.setText("系统没有可用以太网；USB 授权不是网卡驱动。不改模式、不用 Wi-Fi/内置蜂窝回退。");
            return;
        }
        String[] labels = new String[networks.size()];
        for (int position = 0; position < labels.length; position++) labels[position] = "以太网候选 " + (position + 1) + "（未确认厂商）";
        new AlertDialog.Builder(this).setTitle("选择当前直插模块对应的有线候选")
                .setItems(labels, (dialog, which) -> confirm("允许少量流量？", "只在所选系统以太网上请求 example.com 的 HTTPS HEAD，不改变默认网络。DNS/系统代理与上游路径仍需独立核实。", () -> {
                    if (service == null || !service.isHomeRegisteredRecently()) {
                        networkView.setText("模块本地注册状态过期或已断开，未发送流量。");
                        return;
                    }
                    networkBusy = true;
                    networkView.setText("正在测试所选有线网络；不会用平板 Wi-Fi 补救…");
                    networkWorker.execute(() -> {
                        String result = probe.run(networks.get(which));
                        handler.post(() -> {
                            networkBusy = false;
                            if (!isFinishing() && !isDestroyed()) networkView.setText(result);
                        });
                    });
                })).setNegativeButton("取消", null).show();
    }

    private void confirm(String title, String text, Runnable action) {
        new AlertDialog.Builder(this).setTitle(title).setMessage(text)
                .setPositiveButton("确认", (dialog, which) -> action.run()).setNegativeButton("取消", null).show();
    }

    private void render() {
        if (sessionStatus == null) return;
        update(connectionMessages, "阶段：" + ConnectionStatus.stage() + "\n" + ConnectionStatus.message());
        update(sessionStatus, service == null ? "未绑定服务" : service.status());
        if (service != null) {
            update(events, service.eventText());
            update(smsView, service.smsText());
            update(callsView, service.callsText());
            rendering = true;
            polling.setChecked(service.isPolling());
            rendering = false;
        }
        for (Button button : businessButtons) button.setEnabled(service != null && service.isReady());
    }

    private void update(TextView view, String text) { if (!view.getText().toString().equals(text)) view.setText(text); }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    private void heading(String title) { TextView view = text(title); view.setTextSize(20); view.setPadding(0, dp(22), 0, dp(8)); }
    private TextView text(String value) { TextView view = new TextView(this); view.setText(value); view.setTextSize(15); content.addView(view); return view; }
    private EditText input(String hint, int type) { EditText view = new EditText(this); view.setHint(hint); view.setInputType(type); content.addView(view); return view; }
    private Button button(String label, Runnable action) { Button view = new Button(this); view.setText(label); view.setOnClickListener(clicked -> action.run()); content.addView(view); return view; }
    private void businessButton(String label, Runnable action) { businessButtons.add(button(label, action)); }
    private void message(String text) { ConnectionStatus.publish("app_notice", text); connectionMessages.setText(text); }

    @Override protected void onStart() {
        super.onStart();
        bound = bindService(new Intent(this, ModemService.class), binding, Context.BIND_AUTO_CREATE);
        handler.post(refresh);
    }
    @Override protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        refreshInventory(true);
    }
    @Override protected void onStop() {
        handler.removeCallbacks(refresh);
        if (bound) { unbindService(binding); bound = false; }
        service = null;
        super.onStop();
    }
    @Override protected void onDestroy() { networkWorker.shutdownNow(); super.onDestroy(); }
}
