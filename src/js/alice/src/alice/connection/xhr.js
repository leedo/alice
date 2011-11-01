Alice.Connection.XHR = Class.create(Alice.Connection, {
  initialize: function(application) {
    this.type = "xhr";
    this.pings = [];
    this.pingLimit = 10;
    this.seperator = "--xalicex\n";
    this.len = 0;

    this.application = application;
    this.connected = false;
    this.aborting = false;
    this.request = null;
    this.reconnect_count = 0;
    this.reconnecting = false;
  },

  _connect: function() {
    setTimeout(function () {
    var now = new Date();
    var msgid = this.application.msgid();
    this.application.log("opening new connection starting at "+msgid);
    this.changeStatus("ok");
    this.connected = true;
    this.request = new Ajax.Request('/stream', {
      method: 'get',
      parameters: {
        msgid: msgid,
        t: now.getTime() / 1000,
        tab: this.application.activeWindow().id
      },
      on401: this.gotoLogin,
      on500: this.gotoLogin,
      on502: this.gotoLogin,
      on503: this.gotoLogin,
      onException: this.handleException.bind(this),
      onInteractive: this.handleUpdate.bind(this),
      onComplete: this.handleComplete.bind(this)
    });
    }.bind(this), this.application.loadDelay);
  },

  handleUpdate: function(transport) {
    if (this.reconnecting) {
      this.application.activeWindow().showHappyAlert("Reconnected to the Alice server");
      this.reconnecting = false;
    }

    this.reconnect_count = 0;

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
    var data = data.evalJSON();

    this.processQueue(data);

    if (data.time) {
      var lag = this.addPing(time / 1000 -  data.time);

      if (lag > 5) {
        this.application.log("lag is over 5s, reconnecting.");
        this.connect();
      }
    }
  },

  addPing: function(ping) {
    this.pings.push(ping);
    if (this.pings.length > this.pingLimit)
      this.pings.shift();

    var lag = this.lag();
    return lag;
  },

  lag: function() {
    if (!this.pings.length) return 0;
    return this.pings.inject(0, function (acc, n) {return acc + n}) / this.pings.length;
  },

  sendMessage: function(form) {
    if (!this.connected) return false;

    var params;
    if (form.nodeName && form.nodeName == "FORM") {
      params = Form.serialize(form);
    }
    else {
      params = form;
    }

    new Ajax.Request('/say', {
      method: 'post',
      parameters: params,
      on401: this.gotoLogin,
      onException: function (request, exception) {
        alert("There was an error sending a message.");
      }
    });

    return true;
  },

  closeConnection: function() {
    this.aborting = true;
    if (this.request && this.request.transport)
      this.request.transport.abort();
    this.aborting = false;
  },

  closeWindow: function(win) {
    new Ajax.Request('/say', {
      method: 'post',
      on401: this.gotoLogin,
      parameters: {source: win.id, msg: "/close"}
    });
  },

  requestWindow: function(title, windowId, message) {
    new Ajax.Request('/say', {
      method: 'post',
      parameters: {source: windowId, msg: "/create " + title},
      on401: this.gotoLogin,
      onSuccess: function (transport) {
        this.handleUpdate(transport);
        if (message) {
          setTimeout(function() {
            this.application.displayMessage(message) 
          }.bind(this), 1000);
        }
      }.bind(this)
    });
  }

});
