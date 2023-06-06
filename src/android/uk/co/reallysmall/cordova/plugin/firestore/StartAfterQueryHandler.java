package uk.co.reallysmall.cordova.plugin.firestore;

import com.google.firebase.firestore.Query;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;


public class StartAfterQueryHandler implements QueryHandler {
    @Override
    public Query handle(Query query, Object startAfter) {
        JSONObject startAfterJson = (JSONObject) startAfter;

        Map<String, Object> dataMap = (Map<String, Object>) JSONHelper.fromJSON(startAfterJson);
        // Unwrap one more level for '_data'
        Map<String, Object> innerDataMap = (Map<String, Object>) dataMap.get("_data");

        List<Object> orderByValues = new ArrayList<>();
        List<String> orderByFields = QueryHelper.getOrderByFields();


        if(!orderByFields.isEmpty() && !innerDataMap.isEmpty() && innerDataMap.get("exists") instanceof Boolean && (Boolean) innerDataMap.get("exists")){
            Map<String, Object> resultDataMap = (Map<String, Object>) innerDataMap.get("_data");

            for (String field : orderByFields) {
                Object value = resultDataMap.get(field);

                if (value != null) {
                    orderByValues.add(value);
                } 
            }

        }else{
            orderByValues.addAll(dataMap.values());
        }


        return query.startAfter(orderByValues.toArray());
    }
}
