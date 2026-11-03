package com.abandoft.webview_all_android;

import static org.junit.Assert.assertEquals;
import static org.mockito.Mockito.mock;

import io.flutter.plugin.common.MethodChannel;
import java.io.InputStream;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import org.junit.Test;

public class ResourceBridgeTest {
  private InputStream stream(long total, long length, long rangeOffset, byte[] chunk)
      throws Exception {
    final ResourceBridge bridge = new ResourceBridge();
    final Field enabled = ResourceBridge.class.getDeclaredField("enabled");
    enabled.setAccessible(true);
    enabled.setBoolean(bridge, true);
    final Class<?> type = Class.forName(ResourceBridge.class.getName() + "$ResourceInputStream");
    final Constructor<?> constructor =
        type.getDeclaredConstructor(
            ResourceBridge.class,
            MethodChannel.class,
            String.class,
            int.class,
            long.class,
            long.class,
            long.class);
    constructor.setAccessible(true);
    final InputStream stream =
        (InputStream)
            constructor.newInstance(
                bridge, mock(MethodChannel.class), "one", 0, total, length, rangeOffset);
    // Supply an already fetched chunk so these tests exercise the stream
    // contract without dispatching a Dart call on a platform thread.
    final Field buffered = type.getDeclaredField("chunk");
    buffered.setAccessible(true);
    buffered.set(stream, chunk);
    return stream;
  }

  @Test
  public void repeatedLengthQueriesDoNotChangeTheRangeRepresentation() throws Exception {
    try (InputStream input = stream(100, 5, 10, new byte[] {40, 41, 42, 43, 44})) {
      assertEquals(100, input.available());
      assertEquals(100, input.available());
      assertEquals(0, input.read(new byte[0]));
      assertEquals(100, input.available());
      assertEquals(4, input.skip(4));
      assertEquals(100, input.available());
      assertEquals(6, input.skip(6));
      assertEquals(5, input.available());
      assertEquals(5, input.available());
      // Chromium's initial seek must not consume Dart's already sliced bytes.
      assertEquals(40, input.read());
      assertEquals(4, input.available());
    }
  }

  @Test
  public void rangeStartingAtZeroChangesAvailabilityOnlyAfterReading() throws Exception {
    try (InputStream input = stream(100, 3, 0, new byte[] {77, 78, 79})) {
      assertEquals(100, input.available());
      assertEquals(100, input.available());
      assertEquals(77, input.read());
      assertEquals(2, input.available());
      assertEquals(2, input.available());
    }
  }

  @Test
  public void closedStreamHasNoAvailableOrSkippableBytes() throws Exception {
    final InputStream input = stream(100, 5, 10, null);
    input.close();
    assertEquals(0, input.available());
    assertEquals(0, input.available());
    assertEquals(0, input.skip(10));
    assertEquals(-1, input.read());
  }
}
