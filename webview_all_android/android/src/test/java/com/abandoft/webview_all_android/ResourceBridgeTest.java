package com.abandoft.webview_all_android;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import android.os.Handler;
import android.os.Looper;
import io.flutter.plugin.common.MethodChannel;
import java.io.IOException;
import java.io.InputStream;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.ArrayDeque;
import java.util.Collections;
import java.util.Queue;
import org.junit.Test;
import org.mockito.MockedStatic;

public class ResourceBridgeTest {
  private InputStream stream(long total, long length, long rangeOffset, byte[] chunk)
      throws Exception {
    final ResourceBridge bridge = new ResourceBridge();
    setBridgeField(bridge, "enabled", true);
    final Class<?> type = Class.forName(ResourceBridge.class.getName() + "$ResourceInputStream");
    final Constructor<?> constructor =
        type.getDeclaredConstructor(
            ResourceBridge.class,
            MethodChannel.class,
            String.class,
            int.class,
            long.class,
            long.class,
            long.class,
            int.class);
    constructor.setAccessible(true);
    final InputStream stream =
        (InputStream)
            constructor.newInstance(
                bridge, mock(MethodChannel.class), "one", 0, total, length, rangeOffset, 30000);
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

  @Test
  public void queuedCallDoesNotDispatchAfterReconfiguration() throws Exception {
    final QueuedResourceCall call = new QueuedResourceCall();
    when(call.handler.post(any(Runnable.class)))
        .thenAnswer(
            invocation -> {
              setBridgeField(call.bridge, "generation", 1);
              invocation.<Runnable>getArgument(0).run();
              return true;
            });

    assertNull(call.invoke(30000));
    verifyNoInteractions(call.channel);
  }

  @Test
  public void queuedCallDoesNotDispatchAfterTimeout() throws Exception {
    final QueuedResourceCall call = new QueuedResourceCall();
    final Queue<Runnable> pending = new ArrayDeque<>();
    when(call.handler.post(any(Runnable.class)))
        .thenAnswer(invocation -> pending.add(invocation.getArgument(0)));

    final InvocationTargetException error =
        assertThrows(InvocationTargetException.class, () -> call.invoke(1));
    assertEquals(IOException.class, error.getCause().getClass());
    assertEquals("Resource callback timed out.", error.getCause().getMessage());
    pending.remove().run();
    verifyNoInteractions(call.channel);
  }

  private static void setBridgeField(ResourceBridge bridge, String name, Object value)
      throws ReflectiveOperationException {
    final Field field = ResourceBridge.class.getDeclaredField(name);
    field.setAccessible(true);
    field.set(bridge, value);
  }

  private static final class QueuedResourceCall {
    final ResourceBridge bridge = new ResourceBridge();
    final Handler handler = mock(Handler.class);
    final MethodChannel channel = mock(MethodChannel.class);

    QueuedResourceCall() throws ReflectiveOperationException {
      setBridgeField(bridge, "enabled", true);
      setBridgeField(bridge, "main", handler);
    }

    Object invoke(int timeoutMillis) throws ReflectiveOperationException {
      final Method invoke =
          ResourceBridge.class.getDeclaredMethod(
              "invoke", MethodChannel.class, String.class, Object.class, int.class, int.class);
      invoke.setAccessible(true);
      final Looper platformLooper = mock(Looper.class);
      try (MockedStatic<Looper> loopers = mockStatic(Looper.class)) {
        loopers.when(Looper::getMainLooper).thenReturn(platformLooper);
        return invoke.invoke(bridge, channel, "open", Collections.emptyMap(), 0, timeoutMillis);
      }
    }
  }
}
