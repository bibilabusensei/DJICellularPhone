package com.bibilabusensei.djicellular.android.core;

import java.io.Closeable;
import java.io.IOException;

public interface AtTransport extends Closeable {
    void write(byte[] data) throws IOException;
    int read(byte[] buffer, int timeoutMillis) throws IOException;
}
