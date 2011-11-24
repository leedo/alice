Alice.Connection.WebSocket = Class.create(Alice.Connection, {
  initialize: function(application) {
    this.type = "websocket";
    this.application = application;
    this.connected = false;
    this.aborting = false;
    this.request = null;
    this.reconnect_count = 0;
    this.reconnecting = false;
  },

  _connect: function() {
    var now = new Date();
    this.application.log("opening new websocket stream");
    this.changeStatus("ok");
    var parameters = Object.toQueryString({
      t: now.getTime() / 1000,
      tab: this.application.activeWindow().id
    });
    var protocol = (window.location.protocol.match(/^https/) ? "wss://" : "ws://");
    var url = protocol + window.location.host + "/wsstream?" + parameters;
    this.request = new WebSocket(url);
    this.request.onopen = function(){
      this.connected = true;
      this.application.windows().invoke("setupScrollBack");
    }.bind(this);
    this.request.onmessage = this.handleUpdate.bind(this);
    this.request.onerror = this.handleException.bind(this);
    this.request.onclose = this.handleComplete.bind(this);
  },

  handleUpdate: function(e) {
    var data = e.data.evalJSON();
    this.processQueue(data);
  },

  sendMessage: function(form) {
    if (!this.connected) return false;

    var params = form;
    if (form.nodeName && form.nodeName == "FORM") {
      params = Form.serialize(form, true);
    }

    params['stream'] = this.id;
    this.request.send(Object.toJSON(params));
    return true;
  },

  closeConnection: function() {
    this.aborting = true;
    if (this.request) this.request.close();
    this.aborting = false;
  },

  closeWindow: function(win) {
    this.sendMessage({source: win.id, msg: "/close"});
  },

  handleException: function(exception) {
    this.application.log("encountered an error with stream.");
    this.application.log(exception);
    this.connected = false;
    if (!this.aborting)
      setTimeout(this.connect.bind(this), 2000);
    else
      this.changeStatus("ok");
  },

  requestWindow: function(title, windowId, message) {
    this.sendMessage({source: windowId, msg: "/create " + title});
    if (message) {
      setTimeout(function() {
        this.application.displayMessage(message) 
      }.bind(this), 1000);
    }
  }

});
