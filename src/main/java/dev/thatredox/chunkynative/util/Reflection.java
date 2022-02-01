package dev.thatredox.chunkynative.util;

import se.llbit.log.Log;

import java.lang.reflect.Field;

public class Reflection {
    private Reflection() {}

    @SuppressWarnings("unchecked")
    public static <T> T getFieldValue(Object obj, String name, Class<T> cls) {
        try {
            Field field = obj.getClass().getDeclaredField(name);
            field.setAccessible(true);
            Object o = field.get(obj);
            if (o != null && o.getClass() == cls) {
                return (T) o;
            } else {
                Log.errorf("Field %s was of type %s. Expected type %s. Do you have the wrong version of Chunky?",
                        name, o == null ? null : o.getClass(), cls);
                throw new RuntimeException();
            }
        } catch (NoSuchFieldException | IllegalAccessException e) {
            Log.error("Failed to obtain field. Do you have the wrong version of Chunky?", e);
            throw new RuntimeException(e);
        }
    }
}
