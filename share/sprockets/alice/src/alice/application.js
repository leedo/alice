Alice.Application = Class.create({
  initialize: function() {
    this.isFocused = true;
    this.window_map = new Hash();
    this.previousFocus = 0;
    this.connection = new Alice.Connection(this);
    this.filters = [ Alice.makeLinksClickable, Alice.uncacheGravatar ];
    this.monospaceNicks = ['Shaniqua', 'root', 'p6eval'];
    this.keyboard = new Alice.Keyboard(this);
    setTimeout(this.connection.connect.bind(this.connection), 1000);
  },
  
  toggleConfig: function(e) {
    if (this.configWindow && this.configWindow.focus) {
      this.configWindow.focus();

    } else {
      this.configWindow = window.open(null, "config", "resizable=no,scrollbars=no,status=no,toolbar=no,location=no,width=500,height=410");

      this.connection.getConfig(function(transport) {
        this.configWindow.document.write(transport.responseText);
      }.bind(this));
    }
    
    e.stop();
  },
  
  windows: function () {
    return this.window_map.values();
  },
  
  openWindow: function(element, title, active) {
    var win = new Alice.Window(this, element, title, active);
    this.addWindow(win);
    return win;
  },
  
  addWindow: function(win) {
    this.window_map.set(win.id, win);
  },
  
  removeWindow: function(win) {
    if (win.active) this.focusLast();
    this.window_map.unset(win.id);
    this.connection.closeWindow(win);
    win = null;
  },
  
  getWindow: function(windowId) {
    return this.window_map.get(windowId);
  },
  
  activeWindow: function() {
    var windows = this.windows();
    for (var i=0; i < windows.length; i++) {
      if (windows[i].active) return windows[i];
    }
    if (windows[0]) return windows[0];
  },
  
  addFilters: function(list) {
    this.filters = this.filters.concat(list);
  },
  
  applyFilters: function(content) {
    return this.filters.inject(content, function(value, filter) {
      return filter(value);
    });
  },
  
  nextWindow: function() {
    var nextWindow = this.activeWindow().tab.next();
    if (!nextWindow)
      nextWindow = $$('ul#tabs li').first();
    if (!nextWindow) return;
    nextWindow = nextWindow.id.replace('_tab','');
    this.getWindow(nextWindow).focus();
  },
  
  focusLast: function() {
    if (this.previousFocus)
      this.previousFocus.focus();
    else
      this.nextWindow();
  },
  
  previousWindow: function() {
    var previousWindow = this.activeWindow().tab.previous();
    if (!previousWindow)
      previousWindow = $$('ul#tabs li').last();
    if (!previousWindow) return;
    previousWindow = previousWindow.id.replace('_tab','');
    this.getWindow(previousWindow).focus();
  },
  
  closeWindow: function(windowId) {
    var win= this.getWindow(windowId);
    if (win) win.close();
  },
  
  insertWindow: function(windowId, html) {
    if (!$(windowId)) {
      $('windows').insert(html['window']);
      $('tabs').insert(html.tab);
      Alice.makeSortable();
    }
  },
  
  handleActions: function(list) {
    list.each(this.handleAction, this);
  },
  
  handleAction: function(action) {
    switch (action.event) {
      case "join":
        this.insertWindow(action['window'].id, action.html);
        var win = new Alice.Window(this, action['window'].id, action['window'].title, false)
        this.addWindow(win);
        break;
      case "part":
        this.closeWindow(action['window'].id);
        break;
      case "nicks":
        var win = this.getWindow(action['window'].id);
        if (win) win.nicks = action.nicks;
        break;
      case "notice":
        this.activeWindow().addMessage(action);
        break;
      case "clear":
        var win = this.getWindow(action['window'].id);
        if (win) {
          win.messages.update("");
          win.lastNick = "";
        }
        break;
      default:
        break;
    }
  },
  
  displayMessages: function(list) {
    list.each(this.displayMessage, this);
  },
  
  displayMessage: function(message) {
    var win = this.getWindow(message['window'].id);
    if (win) {
      win.addMessage(message);
    } else {
      this.connection.requestWindow(
        message['window'].title, message['window'].id, message
      );
    }
  },
  
  messagesAreMonospacedFor: function(nick) {
    return this.monospaceNicks.indexOf(nick) > -1;
  }
});
