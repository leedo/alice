Alice.Connection = {
  gotoLogin: function() {
    window.location = "/login";
  },
  
  msgid: function() {
    var ids = this.application.windows().map(function(w){return w.msgid});
    return Math.max.apply(Math, ids);
  },
  
  connect: function() {
    if (this.reconnect_count > 3) {
      this.aborting = true;
      this.application.activeWindow().showAlert("Alice server is not responding (<a href='javascript:alice.connection.reconnect()'>reconnect</a>)");
      this.changeStatus("ok");
      return;
    }
    this.pings = [];
    this.closeConnection();
    this.len = 0;
    this.reconnect_count++;

    this.changeStatus("loading");

    var active_window = this.application.activeWindow();
    var other_windows = this.application.windows().filter(function(win){return win.id != active_window.id});

    // called after the first window gets and displays its messages
    var cb = function() {
      setTimeout(function() {

        if (!other_windows.length) {
          this._connect(); 
          return;
        }

        var last = other_windows.pop();
        for (var i=0; i < other_windows.length; i++) {
          this.getWindowMessages(other_windows[i]);
        }
        this.getWindowMessages(last, this._connect.bind(this));
      }.bind(this), this.application.loadDelay);
    }.bind(this);

    this.getWindowMessages(active_window, cb);
  },

  changeStatus: function(classname) {
    $('connection_status').className = classname;
  },
 
  reconnect: function () {
    this.reconnecting = true;
    this.reconnect_count = 0;
    this.connect();
  },

  handleException: function(request, exception) {
    this.application.log("encountered an error with stream.");
    this.application.log(exception);
    this.connected = false;
    if (!this.aborting)
      setTimeout(this.connect.bind(this), 2000);
    else
      this.changeStatus("ok");
  },

  handleComplete: function(transport) {
    this.application.log("connection was closed cleanly.");
    this.connected = false;
    if (!this.aborting)
      setTimeout(this.connect.bind(this), 2000);
    else
      this.changeStatus("ok");
  },
  
  processMessages: function(data) {
    try {
      var queue = data.queue;
      var length = queue.length;
      for (var i=0; i<length; i++) {
        if (queue[i].type == "action")
          this.application.handleAction(queue[i]);
        else if (queue[i].type == "message") {
          if (queue[i].timestamp)
            queue[i].timestamp = Alice.epochToLocal(queue[i].timestamp, this.application.options.timeformat);
          this.application.displayMessage(queue[i]);
        }
      }
    }
    catch (e) {
      this.application.log(e.toString());
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
  
  sendTabOrder: function (windows) {
    new Ajax.Request('/tabs', {
      method: 'post',
      on401: this.gotoLogin,
      parameters: {tabs: windows}
    });
  },
  
  getWindowMessages: function(win, cb) {
    if (!cb) cb = function(){};

    if (win)
      win.active ?
        this.windowQueue.unshift([win, cb]) :
        this.windowQueue.push([win, cb]);

    if (!this.windowWatcher) {
      this.windowWatcher = true;
      this._getWindowMessages();
    }
  },

  _getWindowMessages: function() {
    var item = this.windowQueue.shift();
    var win = item[0],
         cb = item[1];
    var date = new Date();

    this.application.log("requesting messages for "+win.title+" starting at "+win.msgid);
    new Ajax.Request("/messages", {
      method: "get",
      parameters: {source: win.id, msgid: win.msgid, limit: win.messageLimit, time: date.getTime()},
      onSuccess: function(response) {
        this.application.log("inserting messages for "+win.title);
        win.messages.down("ul").insert({bottom: response.responseText});
        win.trimMessages();
        win.setupMessages();
        this.application.log("new msgid for "+win.title+" is "+win.msgid);
        cb();

        if (this.windowQueue.length) {
          this._getWindowMessages();
        } else {
          this.windowWatcher = false;
        }
      }.bind(this)
    });
  }
};
