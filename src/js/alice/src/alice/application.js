Alice.Application = Class.create({
  initialize: function() {
    this.isFocused = true;
    this.window_map = new Hash();
    this.previousFocus = 0;
    this.connection = window.WebSocket ? new Alice.Connection.WebSocket(this) : new Alice.Connection.XHR(this);
    this.filters = [];
    this.keyboard = new Alice.Keyboard(this);

    this.isPhone = window.navigator.platform.match(/(android|iphone)/i) ? 1 : 0;
    this.isMobile = this.isPhone || Prototype.Browser.MobileSafari;
    this.loadDelay = this.isMobile ? 3000 : 1000;

    this.input = new Alice.Input(this, "msg");
    this.submit = $("submit");

    this.submit.observe("click", function (e) {
        this.input.send(); e.stop()}.bind(this));

    // setup UI elements in initial state
    this.makeSortable();
  },
  
  actionHandlers: {
    join: function (action) {
      var win = this.getWindow(action['window'].id);
      if (!win) {
        this.insertWindow(action['window'].id, action.html);
        win = new Alice.Window(this, action['window'].id, action['window'].title, false, action['window'].hashtag);
        this.addWindow(win);
      } else {
        win.enable();
      }
      win.nicks = action.nicks;
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
      if ($('servers')) {
        Alice.connections.connectServer(action.session);
      }
    },
    disconnect: function (action) {
      action.windows.each(function (win_info) {
        var win = this.getWindow(win_info.id);
        if (win) {
          win.disable();
        }
      }.bind(this));
      if ($('servers')) {
        Alice.connections.disconnectServer(action.session);
      }
    },
    focus: function (action) {
      if (!action.window_number) return;
      if (action.window_number == "next") {
        this.nextWindow();
      }
      else if (action.window_number.match(/^prev/)) {
        this.previousWindow();
      }
      else if (action.window_number.match(/^\d+$/)) {
        var tab = $('tabs').down('li', action.window_number);
        if (tab) {
          var window_id = tab.id.replace('_tab','');
          this.getWindow(window_id).focus();
        }
      }
    }
  },
  
  toggleHelp: function() {
    var help = $('help');
    help.visible() ? help.hide() : help.show();
  },

  toggleConfig: function(e) {
    this.connection.getConfig(function (transport) {
      this.input.disabled = true;
      $('container').insert(transport.responseText);
    }.bind(this));
    
    if (e) e.stop();
  },
  
  togglePrefs: function(e) {
    this.connection.getPrefs(function (transport) {
      this.input.disabled = true;
      $('container').insert(transport.responseText);
    }.bind(this));
    
    if (e) e.stop();
  },

  windows: function () {
    return this.window_map.values();
  },

  nth_window: function(n) {
    var tab = $('tabs').down('li', n);
    if (tab) {
      var m = tab.id.match(/([^_]+)_tab/);
      if (m) {
        return this.window_map.get(m[1]);
      }
    }
  },
  
  openWindow: function(element, title, active, hashtag) {
    var win = new Alice.Window(this, element, title, active, hashtag);
    this.addWindow(win);
    if (active) win.focus();
    return win;
  },
  
  addWindow: function(win) {
    this.window_map.set(win.id, win);
    if (window.fluid)
      window.fluid.addDockMenuItem(win.title, win.focus.bind(win));
  },
  
  removeWindow: function(win) {
    if (win.active) this.focusLast();
    if (window.fluid)
      window.fluid.removeDockMenuItem(win.title);
    if (win.id == this.previousFocus.id) {
      this.previousFocus = 0;
    }
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
    var active = this.activeWindow();

    var nextTab = active.tab.next();
    if (!nextTab)
      nextTab = $$('ul#tabs li').first();
    if (!nextTab) return;

    var id = nextTab.id.replace('_tab','');
    if (id != active.id) {
      this.getWindow(id).focus();
    }
  },

  nextUnreadWindow: function() {
    var active = this.activeWindow();
    var tabs = active.tab.nextSiblings().concat(active.tab.previousSiblings().reverse());
    var unread = tabs.find(function(tab) {return tab.hasClassName("unread")});

    if (unread) {
      var id = unread.id.replace("_tab","");
      if (id) {
        this.getWindow(id).focus();
      }
    }
  },
  
  focusLast: function() {
    if (this.previousFocus && this.previousFocus.id != this.activeWindow().id)
      this.previousFocus.focus();
    else
      this.previousWindow();
  },
  
  previousWindow: function() {
    var active = this.activeWindow();

    var previousTab = this.activeWindow().tab.previous();
    if (!previousTab)
      previousTab = $$('ul#tabs li').last();
    if (!previousTab) return;

    var id = previousTab.id.replace('_tab','');
    if (id != active.id)
      this.getWindow(id).focus();
  },
  
  closeWindow: function(windowId) {
    var win = this.getWindow(windowId);
    if (win) win.close();
  },
  
  insertWindow: function(windowId, html) {
    if (!$(windowId)) {
      $('windows').insert(html['window']);
      $('tabs').insert(html.tab);
      $('tab_menu').down('ul').insert(html.select);
      $(windowId+"_tab_overflow").selected = false;
      this.activeWindow().tabOverflowButton.selected = true;
      this.makeSortable();
    }
  },
  
  highlightChannelSelect: function(classname) {
    if (!classname) classname = "unread";
    $('tab_menu').addClassName(classname);
  },
  
  unHighlightChannelSelect: function() {
    $('tab_menu').removeClassName('unread');
    $('tab_menu').removeClassName('highlight');
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

  displayChunk: function(message) {
    var win = this.getWindow(message['window'].id);
    if (win) {
      win.addChunk(message);
    }
  },

  focusHash: function(hash) {
    if (!hash) hash = window.location.hash;
    if (hash) {
      hash = decodeURIComponent(hash);
      hash = hash.replace(/^#/, "");
      var windows = this.windows();
      for (var i = 0; i < windows.length; i++) {
        var win = windows[i];
        if (win.hashtag == hash) {
          if (win && !win.active) win.focus();
          return;
        }
      }
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
          var m = t.id.match(/([^_]+)_tab/);
          if (m) return m[1]
        });
        if (order.length) this.connection.sendTabOrder(order);
      }.bind(this)
    });
  },

  addMissed: function() {
    if (!window.fluid) return;
    window.fluid.dockBadge ? window.fluid.dockBadge++ :
                             window.fluid.dockBadge = 1;
  },

  clearMissed: function() {
    if (!window.fluid) return;
    window.fluid.dockBadge = "";
  },

  ready: function() {
    this.connection.connect();
  },

  log: function () {
    var win = this.activeWindow();
    for (var i=0; i < arguments.length; i++) {
      if (this.options.debug == "true") {
        if (window.console && window.console.log) {
          console.log(arguments[i]);
        }
        if (win) {
          win.addMessage({
            html: '<li class="message monospace"><div class="left">console</div><div class="msg">'+arguments[i].toString()+'</div></li>'
          });
        }
      }
    }
  },

  msgid: function() {
    var ids = this.windows().map(function(w){return w.msgid});
    return Math.max.apply(Math, ids);
  },

  setSource: function(id) {
    $('source').value = id;
  }
 
});
