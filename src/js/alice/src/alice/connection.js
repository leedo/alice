Alice.Connection = Class.create({
  initialize: function(application) {
    this.application = application;
    this.len = 0;
    this.aborting = false;
    this.request = null;
    this.seperator = "--xalicex\n";
    this.msgid = 0;
    this.reconnect_count = 0;
    this.reconnecting = false;
    this.windowQueue = [];
    this.windowWatcher = false;
  },

  gotoLogin: function() {
    window.location = "/login";
  },
  
  closeConnection: function() {
    this.aborting = true;
    if (this.request && this.request.transport)
      this.request.transport.abort();
    this.aborting = false;
  },
  
  connect: function() {
    if (this.reconnect_count > 3) {
      this.aborting = true;
      this.application.activeWindow().showAlert("Alice server is not responding (<a href='javascript:alice.connection.reconnect()'>reconnect</a>)");
      return;
    }
    this.closeConnection();
    this.len = 0;
    this.reconnect_count++;
    var now = new Date();
    this.application.log("opening new connection starting at message " + this.msgid);
    this.request = new Ajax.Request('/stream', {
      method: 'get',
      parameters: {msgid: this.msgid, t: now.getTime() / 1000},
      on401: this.gotoLogin,
      onException: this.handleException.bind(this),
      onInteractive: this.handleUpdate.bind(this),
      onComplete: this.handleComplete.bind(this)
    });
  },
  
  reconnect: function () {
    this.reconnecting = true;
    this.reconnect_count = 0;
    this.connect();
  },

  handleException: function(request, exception) {
    this.application.log("encountered an error with stream.");
    if (!this.aborting)
      setTimeout(this.connect.bind(this), 2000);
  },

  handleComplete: function(transport) {
    this.application.log("connection was closed cleanly.");
    if (!this.aborting)
      setTimeout(this.connect.bind(this), 2000);
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
    try {
      data = data.evalJSON();
      var queue = data.queue;
      var length = queue.length;
      for (var i=0; i<length; i++) {
        if (queue[i].type == "action")
          this.application.handleAction(queue[i]);
        else if (queue[i].type == "message") {
          if (queue[i].msgid) this.msgid = queue[i].msgid;
          if (queue[i].timestamp)
            queue[i].timestamp = Alice.epochToLocal(queue[i].timestamp, this.application.options.timeformat);
          this.application.displayMessage(queue[i]);
        }
      }
    }
    catch (e) {
      this.application.log(e.toString());
    }

    // reconnect if lag is over 5 seconds... not a good way to do this.
    var lag = time / 1000 -  data.time;
    if (lag > 5) {
      this.application.log("lag is " + Math.round(lag) + "s, reconnecting.");
      this.connect();
    }
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
  },
  
  closeWindow: function(win) {
    new Ajax.Request('/say', {
      method: 'post',
      on401: this.gotoLogin,
      parameters: {source: win.id, msg: "/close"}
    });
  },

  getConfig: function(callback) {
    new Ajax.Request('/config', {
      method: 'get',
      on401: this.gotoLogin,
      onSuccess: callback
    });
  },
  
  getPrefs: function(callback) {
    new Ajax.Request('/prefs', {
      method: 'get',
      on401: this.gotoLogin,
      onSuccess: callback
    });
  },
  
  getLog: function(callback) {
    new Ajax.Request('/logs', {
      method: 'get',
      on401: this.gotoLogin,
      onSuccess: callback
    });
  },
  
  sendMessage: function(form) {
    new Ajax.Request('/say', {
      method: 'post',
      parameters: form.serialize(),
      on401: this.gotoLogin,
      onException: function (request, exception) {
        alert("There was an error sending a message.");
      }
    });
  },
  
  sendTabOrder: function (windows) {
    new Ajax.Request('/tabs', {
      method: 'post',
      on401: this.gotoLogin,
      parameters: {tabs: windows}
    });
  },
  
  getWindowMessages: function(win) {
    if (win)
      win.active ? this.windowQueue.unshift(win) : this.windowQueue.push(win);

    if (this.application.isready && !this.windowWatcher) {
      this.windowWatcher = true;
      this._getWindowMessages();
    }
  },

  _getWindowMessages: function() {
    var win = this.windowQueue.shift();

    new Ajax.Request("/messages", {
      method: "get",
      parameters: {source: win.id, limit: win.messageLimit},
      onSuccess: function(response) {
        win.messages.down("ul").replace('<ul class="messages">'+response.responseText+'</ul>');
        win.setupMessages();

        if (this.windowQueue.length) {
          this._getWindowMessages();
        } else {
          this.windowWatcher = false;
        }
      }.bind(this)
    });
  }
});
