package uk.co.reallysmall.cordova.plugin.firestore;

import com.google.firebase.firestore.GeoPoint;

import java.util.Date;
import java.util.Map;

public class JSONDateWrapper extends Date {

    private static String datePrefix = "__DATE:";

    public JSONDateWrapper(Date date) {
        super(date.getTime());
    }

    public static void setDatePrefix(String datePrefix) {
        JSONDateWrapper.datePrefix = datePrefix;
    }

    public static boolean isWrappedDate(Object value) {
        if (value instanceof String && ((String) value).startsWith(datePrefix)) {
            return true;
        } else if (value instanceof Map) {
            Map<String, Object> valueMap = (Map<String, Object>) value;
            return valueMap.containsKey("seconds") && valueMap.containsKey("nanoseconds");
        }
        return false;
    }

    public static Date unwrapDate(Object value) {
        if (value instanceof String) {
            String stringValue = (String) value;
            int prefixLength = datePrefix.length();
            String timestamp = stringValue.substring(prefixLength);
            return new Date(Long.parseLong(timestamp));
        } else if (value instanceof Map) {
            Map<String, Object> valueMap = (Map<String, Object>) value;
            Object secondsObj = valueMap.get("seconds");
            Object nanosecondsObj = valueMap.get("nanoseconds");
            if (secondsObj instanceof Number && nanosecondsObj instanceof Number) {
                long seconds = ((Number) secondsObj).longValue();
                int nanoseconds = ((Number) nanosecondsObj).intValue();
                return new Date(seconds * 1000 + nanoseconds / 1000000);
            }
        }
        return null;
    }

    @Override
    public String toString() {
        return this.datePrefix + this.getTime();
    }
}
