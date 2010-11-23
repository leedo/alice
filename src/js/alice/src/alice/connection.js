Alice.Connection = {
  gotoLogin: function() {
    window.location = "/login";
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
    this._connect();
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
  
  processQueue: function(data) {
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
        else if (queue[i].type == "chunk") {
          this.application.displayChunk(queue[i]);
        }
      }
    }
    catch (e) {
      this.application.log(e.toString());
    }
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
};
