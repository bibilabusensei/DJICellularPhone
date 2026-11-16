package com.bibilabusensei.djicellular.android;

import java.util.ArrayList;
import java.util.List;

final class ConnectionStatus {
    private static final List<String> history = new ArrayList<>();
    private static String stage = "idle";
    private static String message = "等待手动连接；这不是设备检测结果。";

    private ConnectionStatus() { }

    static synchronized void publish(String nextStage, String nextMessage) {
        stage = nextStage;
        message = nextMessage;
        history.add(nextStage + ": " + nextMessage);
        if (history.size() > 24) history.remove(0);
    }

    static synchronized String stage() { return stage; }
    static synchronized String message() { return message; }

    static synchronized String report() {
        StringBuilder result = new StringBuilder("连接阶段: ").append(stage).append('\n').append(message);
        for (String entry : history) result.append('\n').append(entry);
        return result.toString();
    }
}
