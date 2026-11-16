package com.bibilabusensei.djicellular.android.core;

import java.nio.charset.StandardCharsets;
import java.util.Locale;

public final class SmsSubmit {
    public final String pdu;
    public final int tpduLength;

    public SmsSubmit(String recipient, String body) {
        if (recipient == null || !recipient.matches("\\+?[0-9]{3,20}")) {
            throw new IllegalArgumentException("号码只允许 + 和 3–20 位数字，不接受拨号控制字符。");
        }
        if (body == null || body.isEmpty() || body.length() > 70) {
            throw new IllegalArgumentException("当前仅支持单条 UCS-2 短信，最多 70 个字符。");
        }
        for (int position = 0; position < body.length(); position++) {
            if (Character.isSurrogate(body.charAt(position))) {
                throw new IllegalArgumentException("当前不支持 emoji 等非 UCS-2 字符或长短信拆分。");
            }
        }
        boolean international = recipient.startsWith("+");
        String digits = international ? recipient.substring(1) : recipient;
        String padded = digits.length() % 2 == 0 ? digits : digits + "F";
        StringBuilder address = new StringBuilder();
        for (int position = 0; position < padded.length(); position += 2) {
            address.append(padded.charAt(position + 1)).append(padded.charAt(position));
        }
        byte[] text = body.getBytes(StandardCharsets.UTF_16BE);
        StringBuilder payload = new StringBuilder();
        for (byte value : text) {
            payload.append(hexByte(value & 255));
        }
        String tpdu = "0100" + hexByte(digits.length()) + (international ? "91" : "81") +
                address + "0008" + hexByte(text.length) + payload;
        pdu = "00" + tpdu;
        tpduLength = tpdu.length() / 2;
    }

    public static String hexByte(int value) {
        return String.format(Locale.ROOT, "%02X", value);
    }

    public static byte[] decodeHex(String value) {
        if (value == null || value.isEmpty() || value.length() % 2 != 0 ||
                value.length() > 4096 || !value.matches("[0-9A-Fa-f]+")) {
            throw new IllegalArgumentException("Invalid PDU");
        }
        byte[] result = new byte[value.length() / 2];
        for (int position = 0; position < result.length; position++) {
            result[position] = (byte) Integer.parseInt(value.substring(position * 2, position * 2 + 2), 16);
        }
        return result;
    }
}
