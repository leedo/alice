Alice.Connection = Class.create({
  initialize: function () {
    this.len = 0;
    this.aborting = false;
    this.req = null;
    this.seperator = "--xalicex\n";
    this.msgid = 0;
    this.timer = null;
  },
  
  closeConnection: function () {
    this.aborting = true;
    if (this.req && this.req.transport)
      this.req.transport.abort();
    this.aborting = false;
  },
  
  connect: function () {
    this.closeConnection();
    this.len = 0;
    clearTimeout(this.timer);
    var connection = this;
    console.log("opening new connection.");
    this.req = new Ajax.Request('/stream', {
      method: 'get',
      parameters: {msgid: connection.msgid},
      onException: function (req, e) {
        console.log("encountered an error with stream.");
        if (! connection.aborting)
          connection.connect();
      },
      onInteractive: connection.handleUpdate.bind(connection),
      onComplete: function () {
        console.log("connection was closed cleanly.");
        if (! connection.aborting)
          connection.connect();
      }
    });
  },
  
  handleUpdate: function (transport) {
    var time = new Date();
    var data = transport.responseText.slice(this.len);
    var start, end;
    start = data.indexOf(this.seperator);
    if (start > -1) {
      start += this.seperator.length;
      end = data.indexOf(this.seperator, start);
      if (end == -1) return;
    }
    else return;
    this.len += (end + this.seperator.length) - start;
    data = data.slice(start, end);
  
    try {
      data = data.evalJSON();
    }
    catch (err) {
      console.log(err);
      return;
    }
    if (data.msgs.length)
      this.msgid = data.msgs[data.msgs.length - 1].msgid;
    alice.handleActions(data.actions);
    alice.displayMessages(data.msgs);
  },
  
  requestTab: function (name, session, message) {
    var connection = this;
    new Ajax.Request('/say', {
      method: 'get',
      parameters: {session: session, msg: "/window new " + name},
      onSuccess: function (trans) {
        connection.handleUpdate(trans);
        if (message) alice.displayMessage(message);
      }
    });
  },
  
  partChannel: function (channel) {
    new Ajax.Request('/say', {
      method: 'get',
      parameters: {chan: channel.name, session: channel.session, msg: "/part"},
    });
  },
  
  sendMessage: function (form) {
    new Ajax.Request('/say', {
      method: 'get',
      parameters: form.serialize(),
    });
  },
  
  getConfig: function (callback) {
    new Ajax.Request('/config', {
      method: 'get',
      onSuccess: callback
    })
  },
  
  sendConfig: function (params) {
    new Ajax.Request('/save', {
      method: 'get',
      parameters: params
    });
  },
  
  sendPing: function () {
    new Ajax.Request('/ping');
  }
});
