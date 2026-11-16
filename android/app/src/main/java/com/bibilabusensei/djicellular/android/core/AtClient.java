package com.bibilabusensei.djicellular.android.core;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public final class AtClient implements AutoCloseable {
    private static final Set<String> QUERIES = new HashSet<>(Arrays.asList(
            "AT", "AT+GTUSBMODE?", "AT+CPIN?", "AT+CEREG?", "AT+CAVIMS?",
            "AT+CMGF?", "AT+CLCC", "AT+CLAC", "AT+CMGL=4"));
    private final AtTransport transport;
    private final StringBuilder pending = new StringBuilder();
    private volatile boolean closed;
    private boolean poisoned;

    public AtClient(AtTransport transport) {
        this.transport = transport;
    }

    public boolean isUsable() { return !closed && !poisoned; }

    public synchronized List<String> query(String command) throws IOException {
        if (!QUERIES.contains(command)) throw new IllegalArgumentException("未允许的状态命令");
        return execute(command, 6000, false);
    }

    private void ensureReady() throws IOException {
        if (closed || poisoned) throw new IOException("会话已停止；不要自动重试未知结果的操作。");
    }

    private List<String> execute(String command, int timeout, boolean prompt) throws IOException {
        ensureReady();
        try {
            transport.write((command + "\r").getBytes(StandardCharsets.US_ASCII));
            return receive(command, timeout, prompt);
        } catch (IOException failure) {
            poisoned = true;
            throw failure;
        }
    }

    private List<String> receive(String command, int timeout, boolean prompt) throws IOException {
        long deadline = System.nanoTime() + timeout * 1_000_000L;
        List<String> lines = new ArrayList<>();
        int received = 0;
        byte[] buffer = new byte[512];
        while (System.nanoTime() < deadline) {
            ensureReady();
            if (prompt && pending.toString().trim().equals(">")) {
                pending.setLength(0);
                return lines;
            }
            int boundary;
            while ((boundary = pending.indexOf("\n")) >= 0) {
                String line = pending.substring(0, boundary).replace("\r", "").trim();
                pending.delete(0, boundary + 1);
                if (line.isEmpty() || line.equals(command)) continue;
                if (line.equals("OK")) {
                    if (prompt) throw new IOException("未取得短信输入提示，未发送正文。");
                    return lines;
                }
                if (line.equals("ERROR") || line.startsWith("+CME ERROR") || line.startsWith("+CMS ERROR") ||
                        line.equals("NO CARRIER") || line.equals("BUSY") || line.equals("NO ANSWER")) {
                    throw new IOException("模块拒绝或未完成操作：" + errorLabel(line));
                }
                if (!line.equals("RING") && !line.startsWith("+CMTI:") &&
                        !line.startsWith("+CRING:")) lines.add(line);
            }
            int count = transport.read(buffer, 200);
            if (count > 0) {
                received += count;
                if (received > 65536) {
                    poisoned = true;
                    throw new IOException("响应超过 64 KiB，会话已停止。");
                }
                pending.append(new String(buffer, 0, count, StandardCharsets.US_ASCII));
            }
        }
        poisoned = true;
        throw new IOException("模块响应超时，会话已停止，未切模式或自动重试。");
    }

    private String errorLabel(String line) {
        if (line.startsWith("+CMS")) return "SMS ERROR";
        if (line.startsWith("+CME")) return "MODEM ERROR";
        return line;
    }

    public synchronized void requirePduMode() throws IOException {
        List<String> mode = query("AT+CMGF?");
        boolean pduMode = false;
        for (String line : mode) pduMode |= line.matches("\\+CMGF:\\s*0");
        if (!pduMode) {
            throw new IOException("模块当前不是短信 PDU 模式；为保留无人机配置，本 App 不自动修改 CMGF。");
        }
    }

    public synchronized List<String> readMessages() throws IOException {
        requirePduMode();
        return query("AT+CMGL=4");
    }

    public synchronized void sendSms(SmsSubmit submit) throws IOException {
        requirePduMode();
        boolean submitted = false;
        try {
            execute("AT+CMGS=" + submit.tpduLength, 10000, true);
            transport.write((submit.pdu + '\u001a').getBytes(StandardCharsets.US_ASCII));
            submitted = true;
            List<String> response = receive("", 60000, false);
            if (!response.toString().contains("+CMGS:")) {
                throw new IOException("没有取得模块发送确认。");
            }
        } catch (IOException failure) {
            if (!submitted) {
                try { transport.write(new byte[] {27}); } catch (IOException ignored) { }
            }
            poisoned = true;
            throw new IOException(submitted ? "发送结果未知，可能已发送；请先确认，不要重复点击。" :
                    "短信提交未完成，已尝试 ESC 取消输入；请断开会话并确认模块状态。", failure);
        }
    }

    public synchronized void voiceAction(String action, String number) throws IOException {
        List<VoiceCall> calls = VoiceCall.parse(query("AT+CLCC"));
        VoiceCall.requireVoiceOnly(calls);
        String commands = query("AT+CLAC").toString();
        if (!java.util.regex.Pattern.compile("(?<![A-Z0-9_])\\+CHUP(?![A-Z0-9_])").matcher(commands).find()) {
            throw new IOException("未确认专用挂断命令，禁止开始呼叫实验。");
        }
        if (action.equals("dial")) {
            if (number == null || !number.matches("\\+?[0-9]{7,20}")) throw new IllegalArgumentException("实验拨号仅接受 7–20 位普通号码，不接受紧急或短服务号码。");
            if (Arrays.asList("110", "112", "119", "120", "122", "911", "999", "000").contains(number)) {
                throw new IllegalArgumentException("实验版不能用于紧急呼叫。");
            }
            if (!calls.isEmpty()) throw new IOException("已有呼叫，禁止再次拨号。");
            boolean voiceCandidate = false;
            for (String line : query("AT+CAVIMS?")) voiceCandidate |= line.matches("\\+CAVIMS:\\s*1");
            if (!voiceCandidate) {
                throw new IOException("未取得 IMS 语音可用候选状态。");
            }
            execute("ATD" + number + ";", 10000, false);
        } else if (action.equals("answer")) {
            boolean incoming = false;
            for (VoiceCall call : calls) incoming |= call.state == 4 || call.state == 5;
            if (!incoming) throw new IOException("没有待接的语音呼叫。");
            execute("ATA", 10000, false);
        } else if (action.equals("hangup")) {
            if (calls.isEmpty()) throw new IOException("没有语音呼叫，不发送全局挂断。");
            execute("AT+CHUP", 10000, false);
        } else {
            throw new IllegalArgumentException("未知呼叫动作");
        }
    }

    @Override public void close() throws IOException {
        closed = true;
        transport.close();
    }
}
