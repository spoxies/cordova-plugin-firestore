#import "FirestorePlugin.h"
#import "FirestoreTransaction.h"
#import "FirestorePluginJSONHelper.h"

#import <Cordova/CDVAvailability.h>
#include <pthread.h>
#import <os/log.h>

@implementation FirestorePlugin


- (void)pluginInitialize {
    if(![FIRApp defaultApp]) {
        [FIRApp configure];
    }

    self.listeners = [NSMutableDictionary new];
    self.transactions = [NSMutableDictionary new];
}

- (void)collectionOnSnapshot:(CDVInvokedUrlCommand *)command {
    NSString *collection =[command argumentAtIndex:0 withDefault:@"/" andClass:[NSString class]];
    NSArray *queries = [command argumentAtIndex:1 withDefault:@[] andClass:[NSArray class]];
    NSDictionary *options = [command argumentAtIndex:2 withDefault:@{} andClass:[NSDictionary class]];
    NSString *callbackId = [command argumentAtIndex:3 withDefault:@"" andClass:[NSString class]];

    //os_log_debug(OS_LOG_DEFAULT, "Listening to collection");

    FIRCollectionReference *collectionReference = [self.firestore collectionWithPath:collection];

    BOOL includeMetadataChanges = [self getIncludeMetadataChanges:options];

    FIRQuery *query = [self processQueries:queries ForQuery:collectionReference];

    FIRQuerySnapshotBlock snapshotBlock =^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {

        CDVPluginResult *pluginResult;

        if (error != nil) {
            NSLog(@"Collection snapshot listener error %s", [self localError:error]);
            pluginResult = [FirestorePluginResultHelper createPluginErrorResult:error :YES];
        } else {
            pluginResult = [FirestorePluginResultHelper createQueryPluginResult:snapshot :YES];
            //os_log_debug(OS_LOG_DEFAULT, "Got collection snapshot data");
        }

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    };

    id<FIRListenerRegistration> listener;

    listener = [query addSnapshotListenerWithIncludeMetadataChanges:includeMetadataChanges listener:snapshotBlock];

    [self.listeners setObject:listener forKey:callbackId];
}

- (const char * _Nullable)localError:(NSError *)error {
    return [self convertString:[error localizedDescription]];
}
- (const char * _Nullable)convertString:(NSString *)input {
    return [input UTF8String];
}

- (BOOL)getIncludeMetadataChanges:(NSDictionary *)options {

    BOOL queryIncludeMetadataChanges = NO;

    if (options != nil) {

        bool includeDocumentMetadataChanges = [options valueForKey:@"includeDocumentMetadataChanges"];

        if (includeDocumentMetadataChanges) {
            queryIncludeMetadataChanges = YES;
        }

        bool includeQueryMetadataChanges = [options valueForKey:@"includeQueryMetadataChanges"];

        if (includeQueryMetadataChanges) {
            queryIncludeMetadataChanges = YES;
        }

        bool includeMetadataChanges = [options valueForKey:@"includeMetadataChanges"];

        if (includeMetadataChanges) {
            queryIncludeMetadataChanges = YES;
        }
    }

    return queryIncludeMetadataChanges;
}

- (FIRQuery *)processQueries:(NSArray *)queries ForQuery:(FIRQuery *)query {
    // First loop to extract orderBy fields
    NSArray<NSString *> *orderByFields = nil;
    for (NSObject *queryItem in queries) {
        NSString *queryType = [queryItem valueForKey:@"queryType"];
        NSObject *value = [queryItem valueForKey:@"value"];

        if ([queryType isEqualToString:@"orderBy"]) {
            // This assumes value for orderBy is a NSDictionary with 'field' key.
            orderByFields = @[[value valueForKey:@"field"]];
        }
    }
    
    for (NSObject *queryItem in queries) {

        NSString *queryType = [queryItem valueForKey:@"queryType"];
        NSObject *value = [queryItem valueForKey:@"value"];

        //os_log_debug(OS_LOG_DEFAULT, "Query type %s", [self convertString:queryType]);

        if ([queryType isEqualToString:@"limit"]) {
            query = [self processQueryLimit:query ForValue:value];
        } else if ([queryType isEqualToString:@"where"]) {
            query = [self processQueryWhere:query ForValue:value];
        } else if ([queryType isEqualToString:@"orderBy"]) {
            query = [self processQueryOrderBy:query ForValue:value];
        } else if ([queryType isEqualToString:@"startAfter"]) {
            // Use the orderByFields extracted from the first loop
            query = [self processQueryStartAfter:query ForValue:value OrderByFields:orderByFields];
        } else if ([queryType isEqualToString:@"startAt"]) {
            query = [self processQueryStartAt:query ForValue:value];
        } else if ([queryType isEqualToString:@"endAt"]) {
            query = [self processQueryEndAt:query ForValue:value];
        } else if ([queryType isEqualToString:@"endBefore"]) {
            query = [self processQueryEndBefore:query ForValue:value];
        } else {
            NSLog(@"Unknown query type %s", [self convertString:queryType]);
        }
    }

    return query;
}

- (FIRQuery *)processQueryLimit:(FIRQuery *)query ForValue:(NSObject *)value {
    NSNumber *integer = (NSNumber *)value;
    return [query queryLimitedTo:[integer integerValue]];
}

- (FIRQuery *)processQueryWhere:(FIRQuery *)query ForValue:(NSObject *)whereObject {

    NSString *fieldPath = [self unwrapFieldPath:[whereObject valueForKey:@"fieldPath"]];
    NSString *opStr = [whereObject valueForKey:@"opStr"];
    NSObject *value = [self parseWhereValue:[whereObject valueForKey:@"value"]];

    if ([opStr isEqualToString:@"=="]) {
        return [query queryWhereField:fieldPath isEqualTo:value];
    } else if ([opStr isEqualToString:@">"]) {
        return [query queryWhereField:fieldPath isGreaterThan:value];
    } else if ([opStr isEqualToString:@">="]) {
        return [query queryWhereField:fieldPath isGreaterThanOrEqualTo:value];
    } else if ([opStr isEqualToString:@"<"]) {
        return [query queryWhereField:fieldPath isLessThan:value];
    } else if ([opStr isEqualToString:@"<="]) {
        return [query queryWhereField:fieldPath isLessThanOrEqualTo:value];
    } else if ([opStr isEqualToString:@"in"]) {
        return [query queryWhereField:fieldPath in:(NSArray *)value];
    }else if ([opStr isEqualToString:@"array-contains"]) {
        return [query queryWhereField:fieldPath arrayContains:value];
    }else if ([opStr isEqualToString:@"array-contains-any"]) {
        return [query queryWhereField:fieldPath arrayContainsAny:(NSArray *)value];
    }else {
        NSLog(@"Unknown operator type %s", [self convertString:opStr]);
    }

    return query;
}

- (NSString *)unwrapFieldPath:(NSString *)value {
    NSString *stringValue = (NSString *)value;
    
    if ([[stringValue substringToIndex:_fieldPathDocumentIdPrefix.length] isEqualToString:_fieldPathDocumentIdPrefix]) {
        return [stringValue substringFromIndex:_fieldPathDocumentIdPrefix.length];
    }
         
    return value;
}

- (FIRQuery *)processQueryOrderBy:(FIRQuery *)query ForValue:(NSObject *)orderByObject {

    NSString *direction = [orderByObject valueForKey:@"direction"];
    NSString *field = [orderByObject valueForKey:@"field"];

    BOOL directionBool = false;

    if ([direction isEqualToString:@"desc"]) {
      directionBool = true;
    }

    os_log_debug(OS_LOG_DEFAULT, "Order by %s + (%s)", [self convertString:field], [self convertString:direction]);

    return [query queryOrderedByField:field descending:directionBool];
}

- (NSObject *)parseWhereValue:(NSDictionary *)value {
    return [FirestorePluginJSONHelper fromJSON:value ForPlugin:self];
}

- (FIRQuery *)processQueryStartAfter:(FIRQuery *)query ForValue:(id)value OrderByFields:(NSArray<NSString *> *)orderByFields {
    if ([value isKindOfClass:[NSDictionary class]]) {

        NSMutableArray *array = [[NSMutableArray alloc]init];
        NSDictionary *deserializedDictionary = [FirestorePluginJSONHelper fromJSON:(NSDictionary *)value ForPlugin:self];
        NSDictionary *dataDictionary = deserializedDictionary[@"_data"][@"_data"];

        // If orderByFields is available, extract fields, otherwise take whole dictionary
        if (orderByFields) {
            for (NSString *field in orderByFields) {
                id fieldValue = [dataDictionary valueForKeyPath:field];
                if (fieldValue) {
                    [array addObject:fieldValue];
                } else {
                    NSLog(@"Field value for '%@' is nil", field);
                }
            }
        } else {
            array = [NSMutableArray arrayWithObject:dataDictionary];
        }

        query = [query queryStartingAfterValues:array];
        return query;
    }
    else if ([value isKindOfClass:[FIRDocumentSnapshot class]]) {
        FIRDocumentSnapshot *snapshot = (FIRDocumentSnapshot *)value;
        // Handle FIRDocumentSnapshot
        query = [query queryStartingAfterDocument:(FIRDocumentSnapshot *)value];
        return query;
    }
    else {
        NSLog(@"Unsupported value type for startAfter: %@", [value class]);
        return query;
    }
}

- (FIRQuery *)processQueryStartAt:(FIRQuery *)query ForValue:(NSDictionary *)value {
    NSMutableArray *array = [[NSMutableArray alloc]init];
    [array addObject:[FirestorePluginJSONHelper fromJSON:value ForPlugin:self]];
    return [query queryStartingAtValues:array];
}

- (FIRQuery *)processQueryEndAt:(FIRQuery *)query ForValue:(NSDictionary *)value {
    NSMutableArray *array = [[NSMutableArray alloc]init];
    [array addObject:[FirestorePluginJSONHelper fromJSON:value ForPlugin:self]];
    return [query queryEndingAtValues:array];
}

- (FIRQuery *)processQueryEndBefore:(FIRQuery *)query ForValue:(NSDictionary *)value {
    NSMutableArray *array = [[NSMutableArray alloc]init];
    [array addObject:[FirestorePluginJSONHelper fromJSON:value ForPlugin:self]];
    return [query queryEndingBeforeValues:array];
}

- (void)collectionUnsubscribe:(CDVInvokedUrlCommand *)command {
    NSString *callbackId = [command argumentAtIndex:0 withDefault:@"" andClass:[NSString class]];
    [self.listeners[callbackId] remove];
    [self.listeners removeObjectForKey:callbackId];
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)collectionAdd:(CDVInvokedUrlCommand *)command {
    NSString *collection =[command argumentAtIndex:0 withDefault:@"/" andClass:[NSString class]];
    NSDictionary *data = [command argumentAtIndex:1 withDefault:@{} andClass:[NSDictionary class]];

    NSDictionary *parsedData = [FirestorePluginJSONHelper fromJSON:data ForPlugin:self];

    //os_log_debug(OS_LOG_DEFAULT, "Writing document to collection");

    FIRCollectionReference *collectionReference = [self.firestore collectionWithPath:collection];

    __block FIRDocumentReference *ref = [collectionReference addDocumentWithData:parsedData completion:^(NSError * _Nullable error) {

        CDVPluginResult *pluginResult;

        if (error != nil) {
            pluginResult = [FirestorePluginResultHelper createPluginErrorResult:error :NO];
            NSLog(@"Error writing document to collection %s", [self localError:error]);

        } else {
            pluginResult = [FirestorePluginResultHelper createDocumentReferencePluginResult:ref :NO];
            //os_log_debug(OS_LOG_DEFAULT, "Successfully written document to collection");
        }

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)collectionGet:(CDVInvokedUrlCommand *)command {
    NSString *collection =[command argumentAtIndex:0 withDefault:@"/" andClass:[NSString class]];
    NSArray *queries = [command argumentAtIndex:1 withDefault:@[] andClass:[NSArray class]];

    //os_log_debug(OS_LOG_DEFAULT, "Getting document from collection");

    FIRCollectionReference *collectionReference = [self.firestore collectionWithPath:collection];

    FIRQuery *query = [self processQueries:queries ForQuery:collectionReference];

    [query getDocumentsWithCompletion:^(FIRQuerySnapshot * snapshot, NSError * error) {

        CDVPluginResult *pluginResult;

        if (error != nil) {
            NSLog(@"Error getting collection %s", [self localError:error]);
            pluginResult = [FirestorePluginResultHelper createPluginErrorResult:error :NO];
        } else {
            pluginResult = [FirestorePluginResultHelper createQueryPluginResult:snapshot :NO];
            os_log_debug(OS_LOG_DEFAULT, "Successfully got collection");
        }

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)initialise:(CDVInvokedUrlCommand *)command {
    NSDictionary *options = [command argumentAtIndex:0 withDefault:@{} andClass:[NSDictionary class]];

    NSDictionary *config = options[@"config"];

    os_log_debug(OS_LOG_DEFAULT, "Initialising Firestore...");

    if (config != nil && [config objectForKey:@"googleAppId"]) {
        FIROptions *customOptions = [[FIROptions alloc] initWithGoogleAppID:config[@"googleAppID"] GCMSenderID:config[@"gcmSenderID"]];
        if ([config objectForKey:@"bundleID"]) {
          customOptions.bundleID = config[@"bundleID"];
        }
        if ([config objectForKey:@"apiKey"]) {
          customOptions.APIKey = config[@"apiKey"];
        }
        if ([config objectForKey:@"clientId"]) {
          customOptions.clientID = config[@"clientId"];
        }
        if ([config objectForKey:@"databaseUrl"]) {
          customOptions.databaseURL = config[@"databaseUrl"];
        }
        if ([config objectForKey:@"storageBucket"]) {
          customOptions.storageBucket = config[@"storageBucket"];
        }
        if ([config objectForKey:@"projectId"]) {
          customOptions.projectID = config[@"projectId"];
        }

        if ([config objectForKey:@"apiKey"] && [FIRApp appNamed:config[@"apiKey"]] == nil) {
          [FIRApp configureWithName:config[@"apiKey"] options:customOptions];
          FIRApp *customApp = [FIRApp appNamed:config[@"apiKey"]];
          self.firestore = [FIRFirestore firestoreForApp:customApp];
        }
    } else {
        self.firestore = [FIRFirestore firestore];
    }

    FIRFirestoreSettings *settings = self.firestore.settings;

    
    if (options[@"persist"] != NULL) {
        bool persist = [[options valueForKey:@"persist"] boolValue];
        
        [settings setPersistenceEnabled:persist];
        os_log_debug(OS_LOG_DEFAULT, "Setting Firestore persistance to true");
    }

    if (options[@"timestampsInSnapshots"] != NULL) {
        bool timestampsInSnapshots = [[options valueForKey:@"timestampsInSnapshots"] boolValue];

        //[settings setTimestampsInSnapshotsEnabled:timestampsInSnapshots];
        os_log_debug(OS_LOG_DEFAULT, "Setting Firestore timestampsInSnapshots unsupported");
    }

    NSString *datePrefix = options[@"datePrefix"];

    if (datePrefix != NULL) {
        [FirestorePluginJSONHelper setDatePrefix:datePrefix];
    }

    NSString *geopointPrefix = options[@"geopointPrefix"];

    if (geopointPrefix != NULL) {
        [FirestorePluginJSONHelper setGeopointPrefix:geopointPrefix];
    }

    NSString *referencePrefix = options[@"referencePrefix"];

    if (referencePrefix != NULL) {
        [FirestorePluginJSONHelper setReferencePrefix:referencePrefix];
    }

    NSString *timestampPrefix = options[@"timestampPrefix"];

    if (timestampPrefix != NULL) {
        [FirestorePluginJSONHelper setTimestampPrefix:timestampPrefix];
    }

    NSString *fieldValueDelete = options[@"fieldValueDelete"];

    if (fieldValueDelete != NULL) {
        [FirestorePluginJSONHelper setFieldValueDelete:fieldValueDelete];
    }

    NSString *fieldValueServerTimestamp = options[@"fieldValueServerTimestamp"];

    if (fieldValueServerTimestamp != NULL) {
        [FirestorePluginJSONHelper setFieldValueServerTimestamp:fieldValueServerTimestamp];
    }

    NSString *fieldValueIncrement = options[@"fieldValueIncrement"];

    if (fieldValueIncrement != NULL) {
        [FirestorePluginJSONHelper setFieldValueIncrement:fieldValueIncrement];
    }

    NSString *fieldValueArrayUnion = options[@"fieldValueArrayUnion"];

    if (fieldValueArrayUnion != NULL) {
        [FirestorePluginJSONHelper setFieldValueArrayUnion:fieldValueArrayUnion];
    }

    NSString *fieldValueArrayRemove = options[@"fieldValueArrayRemove"];

    if (fieldValueArrayRemove != NULL) {
        [FirestorePluginJSONHelper setFieldValueArrayRemove:fieldValueArrayRemove];
    }

    NSString *fieldPathDocumentId = options[@"fieldPathDocumentId"];

    if (fieldPathDocumentId != NULL) {
        self.fieldPathDocumentIdPrefix = fieldPathDocumentId;
    }

    [self.firestore setSettings:settings];
}

- (void)docSet:(CDVInvokedUrlCommand *)command {
    NSString *collection = [command argumentAtIndex:0 withDefault:@"/" andClass:[NSString class]];
    NSString *docId = [command argumentAtIndex:1 withDefault:@"/" andClass:[NSString class]];
    NSDictionary *data = [command argumentAtIndex:2 withDefault:@{} andClass:[NSDictionary class]];
    NSDictionary *options = [command argumentAtIndex:3 withDefault:@{} andClass:[NSDictionary class]];

    NSDictionary *parsedData = [FirestorePluginJSONHelper fromJSON:data ForPlugin:self];

    BOOL merge = [self getMerge:options];

    //os_log_debug(OS_LOG_DEFAULT, "Setting document. collection: %s, path: %s", [self convertString:collection], [self convertString:docId]);

    FIRDocumentReference *documentReference = [[self.firestore collectionWithPath:collection] documentWithPath:docId];

    DocumentSetBlock block = ^(NSError * _Nullable error) {

        CDVPluginResult *pluginResult;

        if (error != nil) {
            pluginResult = [FirestorePluginResultHelper createPluginErrorResult:error :NO];
            NSLog(@"Error writing document %s", [self localError:error]);

        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
            //os_log_debug(OS_LOG_DEFAULT, "Successfully written document");
        }

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    };

    [documentReference setData:parsedData merge:merge completion:block];
}

- (BOOL)getMerge:(NSDictionary *)options {
    BOOL merge = NO;

    if (options[@"merge"]) {
        merge = YES;
    }

    return merge;
}

- (FIRFirestore *)getFirestore {
    return self.firestore;
}

- (void)docUpdate:(CDVInvokedUrlCommand *)command {
    NSString *collection =[command argumentAtIndex:0 withDefault:@"/" andClass:[NSString class]];
    NSString *docId =[command argumentAtIndex:1 withDefault:@"/" andClass:[NSString class]];
    NSDictionary *data = [command argumentAtIndex:2 withDefault:@{} andClass:[NSDictionary class]];

    NSDictionary *parsedData = [FirestorePluginJSONHelper fromJSON:data ForPlugin:self];

    //os_log_debug(OS_LOG_DEFAULT, "Updating document. collection: %s, path: %s", [self convertString:collection], [self convertString:docId]);

    FIRDocumentReference *documentReference = [[self.firestore collectionWithPath:collection] documentWithPath:docId];

    [documentReference updateData:parsedData completion:^(NSError * _Nullable error) {

        CDVPluginResult *pluginResult;

        if (error != nil) {
            pluginResult = [FirestorePluginResultHelper createPluginErrorResult:error :NO];
            NSLog(@"Error updating document %s", [self localError:error]);

        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
            os_log_debug(OS_LOG_DEFAULT,"Successfully updated document");
        }

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)docOnSnapshot:(CDVInvokedUrlCommand *)command {
    NSString *collection =[command argumentAtIndex:0 withDefault:@"/" andClass:[NSString class]];
    NSString *doc =[command argumentAtIndex:1 withDefault:@"/" andClass:[NSString class]];
    NSString *callbackId = [command argumentAtIndex:2 withDefault:@"" andClass:[NSString class]];

    NSDictionary *options = nil;

    if (command.arguments.count > 3) {
        options = [command argumentAtIndex:3 withDefault:@{} andClass:[NSDictionary class]];
    }

    //os_log_debug(OS_LOG_DEFAULT, "Listening to document");

    FIRDocumentReference *documentReference = [[self.firestore collectionWithPath:collection] documentWithPath:doc];

    BOOL includeMetadataChanges = [self getIncludeMetadataChanges:options];

    FIRDocumentSnapshotBlock snapshotBlock =^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {

        CDVPluginResult *pluginResult;

        if (error != nil) {
            NSLog(@"Document snapshot listener error %s", [self localError:error]);
            pluginResult = [FirestorePluginResultHelper createPluginErrorResult:error :YES];
        } else {

            pluginResult = [FirestorePluginResultHelper createDocumentPluginResult:snapshot :YES];
            //os_log_debug(OS_LOG_DEFAULT,"Got document snapshot data");
        }

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    };

    id<FIRListenerRegistration> listener;

    listener = [documentReference addSnapshotListenerWithIncludeMetadataChanges:includeMetadataChanges listener:snapshotBlock];

    [self.listeners setObject:listener forKey:callbackId];

}

- (void)docUnsubscribe:(CDVInvokedUrlCommand *)command {
    NSString *callbackId = [command argumentAtIndex:0 withDefault:@"" andClass:[NSString class]];
    [self.listeners[callbackId] remove];
    [self.listeners removeObjectForKey:callbackId];
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)docGet:(CDVInvokedUrlCommand *)command {
    NSString *collection =[command argumentAtIndex:0 withDefault:@"/" andClass:[NSString class]];
    NSString *doc =[command argumentAtIndex:1 withDefault:@"/" andClass:[NSString class]];

    //os_log_debug(OS_LOG_DEFAULT, "Listening to document");

    FIRDocumentReference *documentReference = [[self.firestore collectionWithPath:collection] documentWithPath:doc];

    FIRDocumentSnapshotBlock snapshotBlock =^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {

        CDVPluginResult *pluginResult;

        if (error != nil) {
            NSLog(@"Error getting document %s", [self localError:error]);
            pluginResult = [FirestorePluginResultHelper createPluginErrorResult:error :YES];
        } else {
            pluginResult = [FirestorePluginResultHelper createDocumentPluginResult:snapshot :YES];
            //os_log_debug(OS_LOG_DEFAULT,"Successfully got document");
        }

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    };

    [documentReference getDocumentWithCompletion:snapshotBlock];
}

- (void)docDelete:(CDVInvokedUrlCommand *)command {
    NSString *collection =[command argumentAtIndex:0 withDefault:@"/" andClass:[NSString class]];
    NSString *doc =[command argumentAtIndex:1 withDefault:@"/" andClass:[NSString class]];

    //os_log_debug(OS_LOG_DEFAULT, "Deleting document");

    FIRDocumentReference *documentReference = [[self.firestore collectionWithPath:collection] documentWithPath:doc];

    [documentReference deleteDocumentWithCompletion:^(NSError * _Nullable error) {

        CDVPluginResult *pluginResult;

        if (error != nil) {
            NSLog(@"Error deleting document %s", [self localError:error]);
            pluginResult = [FirestorePluginResultHelper createPluginErrorResult:error :YES];
        } else {
            //os_log_debug(OS_LOG_DEFAULT, "Successfully deleted document");
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        }

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (BOOL)timedOut:(time_t)started {
    if (time(nil) - started > 30) {
        return YES;
    }

    return NO;
}

- (void)transactionDocSet:(CDVInvokedUrlCommand *)command {

    NSString *transactionId =[command argumentAtIndex:0 withDefault:@"/" andClass:[NSString class]];
    NSString *docId =[command argumentAtIndex:1 withDefault:@"/" andClass:[NSString class]];
    NSString *collectionPath =[command argumentAtIndex:2 withDefault:@"/" andClass:[NSString class]];
    NSDictionary *data = [command argumentAtIndex:3 withDefault:@{} andClass:[NSDictionary class]];
    NSDictionary *options = [command argumentAtIndex:4 withDefault:@{} andClass:[NSDictionary class]];

    //os_log_debug(OS_LOG_DEFAULT, "Transaction document set for %s", [self convertString:transactionId]);

    FirestoreTransactionQueue *transactionQueue = (FirestoreTransactionQueue *)self.transactions[transactionId];
    FirestoreTransaction *firestoreTransaction = [FirestoreTransaction new];

    firestoreTransaction.docId = docId;
    firestoreTransaction.collectionPath = collectionPath;
    firestoreTransaction.data = data;
    firestoreTransaction.options = options;
    firestoreTransaction.transactionOperationType = (FirestoreTransactionOperationType)SET;

    @synchronized(self) {
        [transactionQueue.queue addObject:firestoreTransaction];
    }

    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
}

- (void)executeTransactionDocSet:(FIRTransaction *)transaction For:(FirestoreTransaction *)firestoreTransaction WithId:(NSString *)transactionId {

    NSDictionary *parsedData = [FirestorePluginJSONHelper fromJSON:firestoreTransaction.data ForPlugin:self];

    BOOL merge = [self getMerge:firestoreTransaction.options];

    //os_log_debug(OS_LOG_DEFAULT, "Execute transaction document set");

    FIRDocumentReference *documentReference = [[self.firestore collectionWithPath:firestoreTransaction.collectionPath] documentWithPath:firestoreTransaction.docId];

    [transaction setData:parsedData forDocument:documentReference merge:merge];
}

- (void)transactionDocUpdate:(CDVInvokedUrlCommand *)command {

    NSString *transactionId =[command argumentAtIndex:0 withDefault:@"/" andClass:[NSString class]];
    NSString *docId =[command argumentAtIndex:1 withDefault:@"/" andClass:[NSString class]];
    NSString *collectionPath =[command argumentAtIndex:2 withDefault:@"/" andClass:[NSString class]];
    NSDictionary *data = [command argumentAtIndex:3 withDefault:@{} andClass:[NSDictionary class]];

    //os_log_debug(OS_LOG_DEFAULT, "Transaction document update for %s", [self convertString:transactionId]);

    FirestoreTransactionQueue *transactionQueue = (FirestoreTransactionQueue *)self.transactions[transactionId];
    FirestoreTransaction *firestoreTransaction = [FirestoreTransaction new];

    firestoreTransaction.docId = docId;
    firestoreTransaction.collectionPath = collectionPath;
    firestoreTransaction.data = data;
    firestoreTransaction.transactionOperationType = (FirestoreTransactionOperationType)UPDATE;

    @synchronized(self) {
        [transactionQueue.queue addObject:firestoreTransaction];
    }

    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
}

- (void)executeTransactionDocUpdate:(FIRTransaction *)transaction For:(FirestoreTransaction *)firestoreTransaction WithId:(NSString *)transactionId {

    NSDictionary *parsedData = [FirestorePluginJSONHelper fromJSON:firestoreTransaction.data ForPlugin:self];

    //os_log_debug(OS_LOG_DEFAULT, "Execute transaction document update");

    FIRDocumentReference *documentReference = [[self.firestore collectionWithPath:firestoreTransaction.collectionPath] documentWithPath:firestoreTransaction.docId];

    [transaction updateData:parsedData forDocument:documentReference];
}

- (void)transactionDocDelete:(CDVInvokedUrlCommand *)command {

    NSString *transactionId =[command argumentAtIndex:0 withDefault:@"/" andClass:[NSString class]];
    NSString *docId =[command argumentAtIndex:1 withDefault:@"/" andClass:[NSString class]];
    NSString *collectionPath =[command argumentAtIndex:2 withDefault:@"/" andClass:[NSString class]];

    //os_log_debug(OS_LOG_DEFAULT, "Transaction document delete for %s", [self convertString:transactionId]);

    FirestoreTransactionQueue *transactionQueue = (FirestoreTransactionQueue *)self.transactions[transactionId];
    FirestoreTransaction *firestoreTransaction = [FirestoreTransaction new];

    firestoreTransaction.docId = docId;
    firestoreTransaction.collectionPath = collectionPath;
    firestoreTransaction.transactionOperationType = (FirestoreTransactionOperationType)DELETE;

    @synchronized(self) {
        [transactionQueue.queue addObject:firestoreTransaction];
    }

    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
}

- (void)executeTransactionDocDelete:(FIRTransaction *)transaction For:(FirestoreTransaction *)firestoreTransaction WithId:(NSString *)transactionId {

    FIRDocumentReference *documentReference = [[self.firestore collectionWithPath:firestoreTransaction.collectionPath] documentWithPath:firestoreTransaction.docId];

    //os_log_debug(OS_LOG_DEFAULT, "Execute transaction document delete");

    [transaction deleteDocument:documentReference];
}

- (void)transactionDocGet:(CDVInvokedUrlCommand *)command {

    [self.commandDelegate runInBackground:^{

        NSString *transactionId =[command argumentAtIndex:0 withDefault:@"/" andClass:[NSString class]];
        NSString *docId =[command argumentAtIndex:1 withDefault:@"/" andClass:[NSString class]];
        NSString *collectionPath =[command argumentAtIndex:2 withDefault:@"/" andClass:[NSString class]];

        //os_log_debug(OS_LOG_DEFAULT, "Transaction document get for %s", [self convertString:transactionId]);

        FirestoreTransactionQueue *transactionQueue = (FirestoreTransactionQueue *)self.transactions[transactionId];
        FirestoreTransaction *firestoreTransaction = [FirestoreTransaction new];

        firestoreTransaction.docId = docId;
        firestoreTransaction.collectionPath = collectionPath;
        firestoreTransaction.transactionOperationType = (FirestoreTransactionOperationType)GET;

        @synchronized(self) {
            [transactionQueue.queue addObject:firestoreTransaction];
            transactionQueue.pluginResult = nil;
        }

        time_t started = time(nil);
        BOOL timedOut = NO;

        CDVPluginResult *pluginResult;

        @synchronized(self) {
            pluginResult = transactionQueue.pluginResult;
        }

        while (pluginResult == nil && timedOut == NO) {

            timedOut = [self timedOut:started];

            @synchronized(self) {
                pluginResult = transactionQueue.pluginResult;
            }
        }

        if (timedOut == YES) {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR] callbackId:command.callbackId];
        } else {
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    }];
}

- (CDVPluginResult *)executeTransactionDocGet:(FIRTransaction *)transaction For:(FirestoreTransaction *)firestoreTransaction WithId:(NSString *)transactionId WithError:(NSError * __autoreleasing *)errorPointer {

    FIRDocumentReference *documentReference = [[self.firestore collectionWithPath:firestoreTransaction.collectionPath] documentWithPath:firestoreTransaction.docId];

    //os_log_debug(OS_LOG_DEFAULT, "Execute transaction document get");

    FIRDocumentSnapshot *snapshot = [transaction getDocument:documentReference error:errorPointer];

    CDVPluginResult *pluginResult;
    
    if (*errorPointer != nil) {
        NSError *error = *errorPointer;
        pluginResult = [FirestorePluginResultHelper createPluginErrorResult:error :NO];
    } else {
        pluginResult = [FirestorePluginResultHelper createDocumentPluginResult:snapshot :NO];
    }

    return pluginResult;
}

- (void)runTransaction:(CDVInvokedUrlCommand *)command {
    NSString *transactionId =[command argumentAtIndex:0 withDefault:@"/" andClass:[NSString class]];

    //os_log_debug(OS_LOG_DEFAULT, "Running transaction");

    [self.firestore runTransactionWithBlock:^id _Nullable(FIRTransaction * _Nonnull transaction, NSError *  __autoreleasing * errorPointer) {

        //os_log_debug(OS_LOG_DEFAULT, "Applying transaction %s", [self convertString:transactionId]);

        FirestoreTransactionQueue *firestoreTransactionQueue = [FirestoreTransactionQueue new];
        firestoreTransactionQueue.queue = [NSMutableArray new];
        firestoreTransactionQueue.pluginResult = nil;

        @synchronized(self) {
            [self.transactions setObject:firestoreTransactionQueue forKey:transactionId];
        }

        NSString *execute = [NSString stringWithFormat:@"Firestore.__executeTransaction('%@');", transactionId];

        [self stringByEvaluatingJavaScriptFromString:execute];

        time_t started = time(nil);

        BOOL timedOut = NO;

        FirestoreTransactionOperationType transactionOperationType = (FirestoreTransactionOperationType)NONE;

        while (transactionOperationType != (FirestoreTransactionOperationType)RESOLVE && timedOut == NO)
        {
            timedOut = [self timedOut:started];

            int count;

            @synchronized(self) {
                count = (int)firestoreTransactionQueue.queue.count;
            }

            while (count == 0 && timedOut == NO) {
                timedOut = [self timedOut:started];

                @synchronized(self) {
                    count = (int)firestoreTransactionQueue.queue.count;
                }
            }

            FirestoreTransaction *firestoreTransaction;

            @synchronized(self) {
                firestoreTransaction = (FirestoreTransaction *)firestoreTransactionQueue.queue[0];
            }

            transactionOperationType = firestoreTransaction.transactionOperationType;

            CDVPluginResult *pluginResult;

            switch (transactionOperationType) {
                case (FirestoreTransactionOperationType)SET:
                    [self executeTransactionDocSet:transaction For:firestoreTransaction WithId:transactionId];
                    break;
                case (FirestoreTransactionOperationType)UPDATE:
                    [self executeTransactionDocUpdate:transaction For:firestoreTransaction WithId:transactionId];
                    break;
                case (FirestoreTransactionOperationType)DELETE:
                    [self executeTransactionDocDelete:transaction For:firestoreTransaction WithId:transactionId];
                    break;
                case (FirestoreTransactionOperationType)GET:
                    pluginResult = [self executeTransactionDocGet:transaction For:firestoreTransaction WithId:transactionId WithError:errorPointer];
                    @synchronized(self) {
                        firestoreTransactionQueue.pluginResult = pluginResult;
                    }
                    break;
                case (FirestoreTransactionOperationType)NONE:
                case (FirestoreTransactionOperationType)RESOLVE:
                    break;
            }

            @synchronized(self) {
                [firestoreTransactionQueue.queue removeObjectAtIndex:0];
            }
        }

        [self.transactions removeObjectForKey:transactionId];

        return firestoreTransactionQueue.result;

    } completion:^(id  _Nullable result, NSError * _Nullable error) {

        CDVPluginResult *pluginResult;

        if (error != nil) {
            pluginResult = [FirestorePluginResultHelper createPluginErrorResult:error :NO];
            NSLog(@"Transaction failure %s", [self localError:error]);
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:result];
            //os_log_debug(OS_LOG_DEFAULT, "Transaction success");
        }

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)transactionResolve:(CDVInvokedUrlCommand *)command {
    NSString *transactionId =[command argumentAtIndex:0 withDefault:@"/" andClass:[NSString class]];
    NSString *result =[command argumentAtIndex:1 withDefault:@"/" andClass:[NSString class]];

    //os_log_debug(OS_LOG_DEFAULT, "Transaction resolve for %s", [self convertString:transactionId]);

    FirestoreTransactionQueue *transactionQueue = (FirestoreTransactionQueue *)self.transactions[transactionId];
    FirestoreTransaction *firestoreTransaction = [FirestoreTransaction new];

    firestoreTransaction.transactionOperationType = (FirestoreTransactionOperationType)RESOLVE;

    @synchronized(self) {
        [transactionQueue.queue addObject:firestoreTransaction];
        transactionQueue.result = result;
    }
}

- (void)batchDocDelete:(CDVInvokedUrlCommand *)command {

}

- (void)batchDocUpdate:(CDVInvokedUrlCommand *)command {

}

- (void)batchDocSet:(CDVInvokedUrlCommand *)command {

}

- (void)batchDoc:(CDVInvokedUrlCommand *)command {

}

- (void)batchCommit:(CDVInvokedUrlCommand *)command {

}

- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script {
    __block NSString *resultString = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.webViewEngine evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
            if (error == nil) {
                if (result != nil) {
                    resultString = [NSString stringWithFormat:@"%@", result];
                }
            } else {
                NSLog(@"evaluateJavaScript error : %s", [self localError:error]);
            }
        }];
    });


    return resultString;
}

- (void)setLogLevel:(CDVInvokedUrlCommand *)command {

  CDVPluginResult *pluginResult = [[CDVPluginResult alloc] init];

  os_log_debug(OS_LOG_DEFAULT,  "This method is not supported in iOS");

  [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}
@end
