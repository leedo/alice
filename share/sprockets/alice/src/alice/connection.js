Alice.Connection = Class.create({
  initialize: function(application) {
    this.application = application;
    this.len = 0;
    this.aborting = false;
    this.request = null;
    this.seperator = "--xalicex\n";
    this.msgid = 0;
  },
  
  closeConnection: function() {
    this.aborting = true;
    if (this.request && this.request.transport)
      this.request.transport.abort();
    this.aborting = false;
  },
  
  connect: function() {
    this.closeConnection();
    this.len = 0;
    var now = new Date();
    //console.log("opening new connection starting at message " + this.msgid);
    this.request = new Ajax.Request('/stream', {
      method: 'get',
      parameters: {msgid: this.msgid, t: now.getTime() / 1000},
      onException: this.handleException.bind(this),
      onInteractive: this.handleUpdate.bind(this),
      onComplete: this.handleComplete.bind(this)
    });
  },

  handleException: function(request, exception) {
    //console.log("encountered an error with stream.");
    if (!this.aborting)
      setTimeout(this.connect.bind(this), 2000);
  },

  handleComplete: function(transport) {
    //console.log("connection was closed cleanly.");
    if (!this.aborting)
      setTimeout(this.connect.bind(this), 2000);
  },
  
  handleUpdate: function(transport) {
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
      var queue = data.queue;
      var length = queue.length;
      for (var i=0; i<length; i++) {
        if (queue[i].type == "action")
          this.application.handleAction(queue[i]);
        else if (queue[i].type == "message") {
          if (queue[i].msgid) this.msgid = queue[i].msgid;
          this.application.displayMessage(queue[i]);
        }
      }
    }
    catch (e) {
      //console.log(e);
    }

    // reconnect if lag is over 5 seconds... not a good way to do this.
    var lag = time / 1000 -  data.time;
    if (lag > 5) {
      //console.log("lag is " + Math.round(lag) + "s, reconnecting.");
      this.connect();
    }
  },
  
  requestWindow: function(title, windowId, message) {
    new Ajax.Request('/say', {
      method: 'get',
      parameters: {source: windowId, msg: "/create " + title},
      onSuccess: function (transport) {
        this.handleUpdate(transport);
        if (message) {
          setTimeout(function() {
            this.application.displayMessage(message) 
          }.bind(this), 1000);
        }
      }.bind(this)
    });
  },
  
  closeWindow: function(win) {
    new Ajax.Request('/say', {
      method: 'get',
      parameters: {source: win.id, msg: "/close"}
    });
  },
  
  getConfig: function(callback) {
    new Ajax.Request('/config', {
      method: 'get',
      onSuccess: callback
    });
  },
  
  getLog: function(callback) {
    new Ajax.Request('/logs', {
      method: 'get',
      onSuccess: callback
    });
  },
  
  sendMessage: function(form) {
    new Ajax.Request('/say', {
      method: 'get',
      parameters: form.serialize(),
    });
  },
  
  sendTabOrder: function (windows) {
    new Ajax.Request('/tabs', {
      method: 'get',
      parameters: {tabs: windows}
    });
  },
  
  sendPing: function() {
    new Ajax.Request('/ping');
  }
});
