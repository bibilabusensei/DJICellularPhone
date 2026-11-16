package com.bibilabusensei.djicellular.android.core;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class VoiceCall {
    public final int index;
    public final int state;
    public final int mode;
    private static final Pattern RECORD = Pattern.compile("^\\+CLCC:\\s*(\\d+),\\s*[01],\\s*([0-6]),\\s*(\\d+),.*$");

    private VoiceCall(int index, int state, int mode) {
        this.index = index;
        this.state = state;
        this.mode = mode;
    }

    public static List<VoiceCall> parse(List<String> lines) {
        List<VoiceCall> calls = new ArrayList<>();
        for (String line : lines) {
            if (!line.startsWith("+CLCC:")) continue;
            Matcher matcher = RECORD.matcher(line);
            if (!matcher.matches()) throw new IllegalArgumentException("无法安全解析呼叫列表，停止呼叫操作。");
            calls.add(new VoiceCall(Integer.parseInt(matcher.group(1)),
                    Integer.parseInt(matcher.group(2)), Integer.parseInt(matcher.group(3))));
        }
        return calls;
    }

    public static void requireVoiceOnly(List<VoiceCall> calls) {
        for (VoiceCall call : calls) {
            if (call.mode != 0) {
                throw new IllegalStateException("存在数据/未知呼叫，禁止拨号、接听或挂断，避免中断模块数据。");
            }
        }
    }
}
