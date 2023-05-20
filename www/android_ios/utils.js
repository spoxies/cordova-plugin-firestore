function AutoId() {
}

AutoId.prototype = {
  newId: function() {
    // alphanumeric characters
    var chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    var autoId = '';
    for (var i = 0; i < 20; i++) {
      autoId += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    if (autoId.length !== 20) {
      throw new Error('Invalid auto ID: ' + autoId);
    }
    return autoId;
  }
};

function getOrGenerateId(id) {
  if (typeof id === 'string') {
      // check if id string contains a ','
      if(id.includes(',')) {
        // if so only return part after the comma
        let parts = id.split(',');
        return parts[1];
      }
    return id;
  }

  return new AutoId().newId();
}



module.exports = {
  AutoId: AutoId,
  getOrGenerateId: getOrGenerateId
};
