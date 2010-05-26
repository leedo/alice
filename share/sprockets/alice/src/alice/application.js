Alice.Application = Class.create({
  initialize: function() {
    this.isFocused = true;
    this.window_map = new Hash();
    this.previousFocus = 0;
    this.connection = new Alice.Connection(this);
    this.filters = [];
    this.monospaceNicks = ['Shaniqua', 'root', 'p6eval'];
    this.keyboard = new Alice.Keyboard(this);
    
    // Keep this as a timeout so the page doesn't show "loading..."
    setTimeout(this.connection.connect.bind(this.connection), 1000);
    
    // setup UI elements in initial state
    this.makeSortable();
    var active = this.activeWindow();
    if (active) {
      active.input.focus();
      active.scrollToBottom();
    }
  },
  
  actionHandlers: {
    join: function (action) {
      var win = this.getWindow(action['window'].id);
      if (!win) {
        this.insertWindow(action['window'].id, action.html);
        win = new Alice.Window(this, action['window'].id, action['window'].title, false);
        this.addWindow(win);
      } else {
        win.enable();
        win.nicks = action.nicks;
      }
    },
    part: function (action) {
      this.closeWindow(action['window'].id);
    },
    nicks: function (action) {
      var win = this.getWindow(action['window'].id);
      if (win) win.nicks = action.nicks;
    },
    alert: function (action) {
      this.activeWindow().showAlert(action['body']);
    },
    clear: function (action) {
      var win = this.getWindow(action['window'].id);
      if (win) {
        win.messages.down("ul").update("");
        win.lastNick = "";
      }
    },
    connect: function (action) {
      action.windows.each(function (win_info) {
        var win = this.getWindow(win_info.id);
        if (win) {
          win.enable();
        }
      }.bind(this));
      if (this.configWindow) {
        this.configWindow.connectServer(action.session);
      }
    },
    disconnect: function (action) {
      action.windows.each(function (win_info) {
        var win = this.getWindow(win_info.id);
        if (win) {
          win.disable();
        }
      }.bind(this));
      if (this.configWindow) {
        this.configWindow.disconnectServer(action.session);
      }
    }
  },
  
  toggleConfig: function(e) {
    if (this.configWindow && !this.configWindow.closed && this.configWindow.focus) {
      this.configWindow.focus();
    } else {
      this.configWindow = window.open(null, "config", "resizable=no,scrollbars=no,status=no,toolbar=no,location=no,width=500,height=480");
      this.connection.getConfig(function (transport) {
        this.configWindow.document.write(transport.responseText);
      }.bind(this));
    }
    
    e.stop();
  },
  
  togglePrefs: function(e) {
    if (this.prefWindow && !this.prefWindow.closed && this.prefWindow.focus) {
      this.prefWindow.focus();
    } else {
      this.prefWindow = window.open(null, "prefs", "resizable=no,scrollbars=no,status=no,toolbar=no,location=no,width=200,height=300");
      this.connection.getPrefs(function (transport) {
        this.prefWindow.document.write(transport.responseText);
      }.bind(this));
    }
    
    e.stop();
  },

  toggleLogs: function(e) {
    if (this.logWindow && !this.logWindow.closed && this.logWindow.focus) {
      this.logWindow.focus();
    } else {
      this.logWindow = window.open(null, "logs", "resizable=no,scrollbars=no,statusbar=no, toolbar=no,location=no,width=500,height=480");
      this.connection.getLog(function (transport) {
        this.logWindow.document.write(transport.responseText);
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
      $('tab_overflow_overlay').insert(html.select);
      $(windowId+"_tab_overflow_button").selected = false;
      this.activeWindow().tabOverflowButton.selected = true;
      this.makeSortable();
    }
  },
  
  highlightChannelSelect: function() {
    var img = $('tab_overflow_button').down('img');
    img.src = img.src.replace('overflow.png','overflow-active.png');
  },
  
  unHighlightChannelSelect: function() {
    var img = $('tab_overflow_button').down('img');
    img.src = img.src.replace('overflow-active.png','overflow.png');
  },
  
  updateChannelSelect: function() {
    var windows = this.windows();
    for (var i=0; i < windows.length; i++) {
      var win = windows[i];
      if ((win.tab.hasClassName('unread') || win.tab.hasClassName('highlight')) && win.isTabWrapped()) {
        this.highlightChannelSelect();
        return;
      }
    }
    this.unHighlightChannelSelect();
  },
  
  handleAction: function(action) {
    if (this.actionHandlers[action.event]) {
      this.actionHandlers[action.event].call(this,action);
    }
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
  },
  
  focusHash: function(hash) {
    var hash = window.location.hash;
    if (hash) {
      hash = hash.replace(/^#/, "");
      var focus = this.getWindow(hash)
      if (focus && !focus.active) focus.focus();
    }
  },
  
  makeSortable: function() {
    Sortable.create('tabs', {
      overlap: 'horizontal',
      constraint: 'horizontal',
      format: /(.+)/,
      onUpdate: function (res) {
        var tabs = res.childElements();
        var order = tabs.collect(function(t){
          var m = t.id.match(/(w[^_]+)_tab/);
          if (m) return m[1]
        });
        if (order.length) this.connection.sendTabOrder(order);
      }.bind(this)
    });
  }
});
