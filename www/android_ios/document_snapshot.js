/* global Promise: false, Firestore: false, FirestoreTimestamp: false */

var FirestoreTimestamp = require("./firestore_timestamp");
var GeoPoint = require("./geo_point");
var DocumentReference;
var CollectionReference;
var Path = require("./path");

function DocumentSnapshot(data) {

  this._data = data;

  if (data.exists) {
    DocumentSnapshot._reads++;
    this._data._data = this._parse(this._data._data);
  }
}

DocumentSnapshot._reads = 0;

DocumentSnapshot.prototype = {
  _newDocumentReference: function(documentPath) {
    if (DocumentReference === undefined) {
      DocumentReference = require('./document_reference');
    }
  
    if (CollectionReference === undefined) {
      CollectionReference = require('./collection_reference');
    }

    var path = new Path(documentPath);
    return new DocumentReference(new CollectionReference(path.parent), path.id);
  },
  _parse: function (data) {
    var keys = Object.keys(data);

    for (var i = 0; i < keys.length; i++) {
      var key = keys[i];

      if (Object.prototype.toString.call(data[key]) === '[object String]') {

        if (data[key].startsWith(Firestore.options().datePrefix)) {
          var length = data[key].length;
          var prefixLength = Firestore.options().datePrefix.length;

          var timestamp = data[key].substr(prefixLength, length - prefixLength);
          data[key] = new Date(parseInt(timestamp));

        } else if (data[key].startsWith(Firestore.options().timestampPrefix)) {
          var length = data[key].length;
          var prefixLength = Firestore.options().timestampPrefix.length;

          var timestamp = data[key].substr(prefixLength, length - prefixLength);

          if (timestamp.includes("_")) {
            var timestampParts = timestamp.split("_");
            data[key] = new FirestoreTimestamp(parseInt(timestampParts[0]), parseInt(timestampParts[1]));

          } else {
            data[key] = new FirestoreTimestamp(parseInt(timestamp), 0);
          }
        } else if (data[key].startsWith(Firestore.options().geopointPrefix)) {
          var length = data[key].length;
          var prefixLength = Firestore.options().geopointPrefix.length;

          var geopoint = data[key].substr(prefixLength, length - prefixLength);

          if (geopoint.includes(",")) {
            var geopointParts = geopoint.split(",");
            data[key] = new GeoPoint(parseFloat(geopointParts[0]), parseFloat(geopointParts[1]));
          }
        } else if (data[key].startsWith(Firestore.options().referencePrefix)) {
          var length = data[key].length;
          var prefixLength = Firestore.options().referencePrefix.length;

          var reference = data[key].substr(prefixLength, length - prefixLength);

          data[key] = this._newDocumentReference(reference);
          
        } else if (Object.prototype.toString.call(data[key]) === '[object Object]') {
          data[key] = this._parse(data[key]);
        }
      } else if (Array.isArray(data[key])) {

        data[key] = this._parse(data[key]);
      }
    }

    return data;
  },
  _fieldPath: function (obj, i) {
    return obj[i];
  },
  data: function () {
    return this._data._data;
  },
  get: function (fieldPath) {
    return fieldPath.split('.').reduce(this._fieldPath, this._data);
  }
};

Object.defineProperties(DocumentSnapshot.prototype, {
  exists: {
    get: function () {
      return this._data.exists;
    }
  },
  id: {
    get: function () {
      return this._data.id;
    }
  },
  metadata: {
    get: function () {
      throw "DocumentReference.metadata: Not supported";
    }
  },
  ref: {
    get: function () {
      return this._data.ref;
    }
  }
});

module.exports = DocumentSnapshot;
