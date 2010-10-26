Alice.Connection.WebSocket = Class.create(Alice.Connection, {
  initialize: function(application) {
    this.application = application;
    this.connected = false;
    this.aborting = false;
    this.request = null;
    this.reconnect_count = 0;
    this.reconnecting = false;
    this.windowQueue = [];
    this.windowWatcher = false;
  },

  _connect: function() {
    var now = new Date();
    var msgid = this.application.msgid();
    this.application.log("opening new websocket connection starting at "+msgid);
    this.changeStatus("ok");
    this.connected = true;
    var parameters = Object.toQueryString({
      msgid: msgid,
      t: now.getTime() / 1000,
      tab: this.application.activeWindow().id
    });
    var url = "ws://" + window.location.host + "/wsstream?" + parameters;
    this.request = new WebSocket(url);
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
      params = form.serialize(true);
    }

    console.log(params);
    this.request.send(Object.toJSON(params));
    return true;
  },

  closeConnection: function() {
    this.aborting = true;
    if (this.request) this.request.close();
    this.aborting = false;
  },

  closeWindow: function(win) {
    this.request.send(Object.toJSON(
      {source: win.id, msg: "/close"}
    ));
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



});
