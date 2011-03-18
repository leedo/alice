Alice.Application = Class.create({
  initialize: function() {
    this.options = {};
    this.isFocused = true;
    this.window_map = new Hash();
    this.previousFocus = 0;
    this.selectedSet = '';
    this.tabs = $('tabs');
    this.topic = $('topic');
    this.nicklist = $('nicklist');
    this.topic_height = "14px";
    this.connection = window.WebSocket ? new Alice.Connection.WebSocket(this) : new Alice.Connection.XHR(this);
    this.filters = [];
    this.keyboard = new Alice.Keyboard(this);
    this.supportsTouch = 'createTouch' in document;

    this.isPhone = window.navigator.userAgent.match(/(android|iphone)/i) ? true : false;
    this.isMobile = this.isPhone || Prototype.Browser.MobileSafari || Prototype.Browser.Gecko;
    this.loadDelay = this.isMobile ? 3000 : 1000;
    if (window.navigator.standalone) this.loadDelay = 0;

    this.input = new Alice.Input(this, "msg");
    this.submit = $("submit");

    this.submit.observe("click", function (e) {
        this.input.send(); e.stop()}.bind(this));

    // setup UI elements in initial state
    this.makeSortable();
    this.setupTopic();
    this.setupNicklist();
    this.setupMenus();
    
    this.oembeds = [
      [/https?:\/\/.*\.flickr.com\/.*/i],
      [/https?:\/\/www\.youtube\.com\/watch.*/i],
      [/https?:\/\/.*\.wikipedia.org\/wiki\/.*/i],
      [/https?:\/\/.*\.twitpic\.com\/.*/i],
      [/https?:\/\/www\.hulu\.com\/watch\/.*/i],
      [/https?:\/\/(:?www\.)?vimeo\.com\/.*/i],
      [/https?:\/\/(:?www\.)?vimeo\.com\/groups\/.*\/videos\/.*/i],
      [/https?:\/\/.*\.funnyordie\.com\/videos\/.*/i]
    ];
    this.jsonp_callbacks = {};
  },

  addOembedCallback: function(id, win) {
    this.jsonp_callbacks[id] = function (data) {
      delete this.jsonp_callbacks[id];
      if (!data) return;
      if (!data.html && data.type == "photo")
        data.html = "<a href=\""+data.url+"\" target=\"_blank\">"
                  + "<img src=\""+this.options.image_prefix+data.url+"\">"
                  + "</a>";
      if (!data.html) return;
      this.insertOembedContent($(id), data, win);
    }.bind(this);
    return "alice.jsonp_callbacks['"+id+"']";
  },

  insertOembedContent: function(a, data, win) {
    if (data.title) a.update(data.title);
    var container = new Element("div", {"class": "oembed_container"});
    var div = new Element("div", {"class": "oembed"});
    a.observe("click", function(e) {
      e.stop();
      var state = container.style.display;
      if (state != "block") {
        var scroll = win.shouldScrollToBottom();
        container.style.display = "block";
        if (scroll) win.scrollToBottom(true);
      }
      else {
        container.style.display = "none";
      }
    });

    div.insert(data.html);
    container.insert(div);
    container.insert("<div class='oembed_clearfix'></div>");
    a.insert({after: container});
    a.insert({after: ' <em>on <a href="'+a.href+'" class="external" target="_blank">'+data.provider_name+'<img src="/static/image/external.png" /></a></em>'});
  },
  
  actionHandlers: {
    join: function (action) {
      var win = this.getWindow(action['window'].id);
      if (!win) {
        this.insertWindow(action['window'].id, action.html);
        win = this.openWindow(action['window']);
        if (this.selectedSet && !this.currentSetContains(win)) {
          if (confirm("You joined "+win.title+" which is not in the '"+this.selectedSet+"' set. Do you want to add it?")) {
            this.tabsets[this.selectedSet].push(win.id);
            win.show();
            Alice.tabsets.submit(this.tabsets);
          }
          else {
            win.hide();
          }
        }
      }
      win.updateNicks(action.nicks);
    },
    part: function (action) {
      this.closeWindow(action['window'].id);
    },
    nicks: function (action) {
      var win = this.getWindow(action['window'].id);
      if (win) win.updateNicks(action.nicks);
    },
    alert: function (action) {
      this.activeWindow().showAlert(action['body']);
    },
    clear: function (action) {
      var win = this.getWindow(action['window'].id);
      if (win) {
        win.messages.update("");
        win.lastNick = "";
      }
    },
    announce: function (action) {
      this.activeWindow().announce(action['body']);
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
        var tab = this.tabs.down('li', action.window_number);
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

  toggleTabsets: function(e) {
    this.connection.getTabsets(function (transport) {
      this.input.disabled = true;
      $('container').insert(transport.responseText);
      Alice.tabsets.focusIndex(0);
    }.bind(this));
  },

  windows: function () {
    return this.window_map.values();
  },

  nth_window: function(n) {
    var tab = this.tabs.down('.visible:not(.info_tab)', n - 1);
    if (tab) {
      var m = tab.id.match(/([^_]+)_tab/);
      if (m) {
        return this.window_map.get(m[1]);
      }
    }
  },
  
  openWindow: function(serialized) {
    var win = new Alice.Window(this, serialized);
    this.addWindow(win);
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
    for (var i=0; i < windows.length; i++) {
      if (windows[i].type != "info") return windows[i];
    }
    if (windows[0]) return windows[0];
  },
  
  addFilters: function(list) {
    this.filters = this.filters.concat(list);
  },
  
  applyFilters: function(msg, win) {
    if (msg.hasClassName("filtered")) return;
    this.filters.each(function(f){
      f(msg, win);
    });
    msg.addClassName("filtered");
  },
  
  nextWindow: function() {
    var active = this.activeWindow();

    var nextTab = active.tab.next('.visible');
    if (!nextTab) nextTab = this.tabs.down('.visible');
    if (!nextTab) return;

    var id = nextTab.id.replace('_tab','');
    if (id != active.id) {
      var win = this.getWindow(id);
      win.focus();
      return win;
    }
  },

  updateOverflowMenus: function() {
    var left = "";
    var right = "";

    this.windows().each(function(win) {
      var tab = win.tab;
      var position = win.getTabPosition();
      if (position.tab.overflow_left) {
        left += '<li rel="'+win.id+'">'+win.title.escapeHTML()+'</li>';
      }
      if (position.tab.overflow_right) {
        right += '<li rel="'+win.id+'">'+win.title.escapeHTML()+'</li>';
      }
    }.bind(this));

    $('tab_menu_right').down('ul').update(right);
    $('tab_menu_left').down('ul').update(left);

    this.toggleOverflow("left", !!left);
    this.toggleOverflow("right", !!right);
  },

  toggleOverflow: function(side, visible) {
    var display = (visible ? "block" : "none");
    var opacity = (visible ? 1 : 0);
    $('tab_menu_'+side).style.opacity = opacity;
  },

  nextUnreadWindow: function() {
    var active = this.activeWindow();
    var tabs = active.tab.nextSiblings().concat(active.tab.previousSiblings().reverse());
    var unread = tabs.find(function(tab) {
      return tab.hasClassName("unread") && tab.hasClassName("visible")
    });

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

    var previousTab = this.activeWindow().tab.previous('.visible');
    if (!previousTab) previousTab = this.tabs.select('.visible').last();
    if (!previousTab) return;

    var id = previousTab.id.replace('_tab','');
    if (id != active.id) this.getWindow(id).focus();
  },
  
  closeWindow: function(windowId) {
    var win = this.getWindow(windowId);
    if (win) win.close();
  },
  
  insertWindow: function(windowId, html) {
    if (!$(windowId)) {
      $('windows').insert(html['window']);
      $('tabs').insert(html.tab);
      this.makeSortable();
    }
  },
  
  highlightChannelSelect: function(id, classname) {
    if (!classname) classname = "unread";
    ['tab_menu_left', 'tab_menu_right'].each(function(menu) {
      menu = $(menu);

      menu.select('li').each(function(li) {
        if (li.getAttribute('rel') == id) {
          li.addClassName(classname);
          menu.addClassName(classname);
          return;
        }
      });
    });
  },
  
  unHighlightChannelSelect: function(id) {
    ['tab_menu_left', 'tab_menu_right'].each(function(menu) {
      menu = $(menu);

      menu.select('li').each(function(li) {
        if (li.getAttribute('rel') == id) {
          li.removeClassName("unread");
          li.removeClassName("highlight");
          return;
        }
      });

      ["unread", "highlight"].each(function(c) {
        if (!menu.select('li').any(function(li) {return li.hasClassName(c)})) {
          menu.removeClassName(c);
        }
      });
    });
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
      hash = decodeURI(hash);
      hash = hash.replace(/^#/, "");

      if (hash.substr(0,1) != "/") {
        var name = hash.match(/^([^\/]+)/)[0];
        hash = hash.substr(name.length);
        if (this.tabsets[name]) {
          if (this.selectedSet != name) this.showSet(name);
        }
        else {
          window.location.hash = hash;
          window.location = window.location.toString();
          return false;
        }
      }

      var windows = this.windows();
      for (var i = 0; i < windows.length; i++) {
        var win = windows[i];
        if (win.hashtag == hash) {
          if (!win.active) win.focus();
          return true;
        }
      }
    }
    return false;
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

    // required due to browser weirdness with scrolltobottom on initial focus
    setTimeout(function(){
      this.focusHash() || this.activeWindow().focus();
      this.activeWindow().scrollToBottom(true)
    }.bind(this), 10);
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
  },

  showSet: function(name) {
    var ids = this.tabsets[name];
    if (ids) {
      var elem = $('tabset_menu').select('li').find(function(li) {
        return li.innerHTML.strip() == name;
      });
      elem.up('ul').select('li').invoke('removeClassName', 'selectedset');
      elem.addClassName('selectedset');

      this.windows().filter(function(win) {
        return win.type != "privmsg";
      }).each(function(win) {
        ids.indexOf(win.id) >= 0 ? win.show() : win.hide();
      });

      this.selectSet(name);

      var active = this.activeWindow();

      if (!active.visible) {
        active = this.nextWindow();
      }

      if (active) active.shiftTab();
    }
  },

  selectSet: function(name) {
    var hash = window.location.hash;
    hash = hash.replace(/^[^\/]*/, name);
    window.location.hash = hash;
    window.location = window.location.toString();
    this.selectedSet = name;
  },

  clearSet: function(elem) {
    elem.up('ul').select('li').invoke('removeClassName', 'selectedset');
    elem.addClassName('selectedset');
    this.windows().invoke("show");
    this.selectSet('');
    this.activeWindow().shiftTab();
  },

  currentSetContains: function(win) {
    var set = this.selectedSet;
    if (win.type == "channel" && set && this.tabsets[set]) {
      return (this.tabsets[set].indexOf(win.id) >= 0);
    }
    return true;
  },

  displayTopic: function(new_topic) {
    this.topic.update(new_topic || "no topic set");
    this.filters[0](this.topic);
  },

  displayNicks: function(nicks) {
    this.nicklist.innerHTML = nicks.sort(function(a, b) {
      a = a.toLowerCase();
      b = b.toLowerCase();
      if (a > b) 
        return 1 
      if (a < b) 
        return -1 
      return 0;
    }).map(function(nick) {
      return "<li>"+nick.escapeHTML()+"</li>";
    }).join("");
  },

  toggleNicklist: function() {
    var windows = $('windows');
    var win = this.activeWindow();
    var scroll = win.shouldScrollToBottom();
    if (windows.hasClassName('nicklist'))
      windows.removeClassName('nicklist');
    else
      windows.addClassName('nicklist');
    if (scroll) win.scrollToBottom(true);
  },

  setupNicklist: function() {
    this.nicklist.observe(this.supportsTouch ? "touchstart" : "click", function(e) {
      if (this.supportsTouch) e.stop();
      var li = e.findElement('li');
      if (li) {
        var nick = li.innerHTML;
        this.connection.requestWindow(nick, this.activeWindow().id);
      }
    }.bind(this));
  },

  setupTopic: function() {
    this.topic.observe(this.supportsTouch ? "touchstart" : "click", function(e) {
      if (this.supportsTouch) e.stop();
      if (this.topic.getStyle("height") == this.topic_height) {
        this.topic.setStyle({height: "auto"});
      } else {
        this.topic.setStyle({height: this.topic_height});
      }
    }.bind(this));
  },

  setupMenus: function() {
    var click = this.supportsTouch ? "touchend" : "mouseup";

    $('config_menu').observe(click, function(e) {
      var li = e.findElement(".dropdown li");
      if (li) {
        e.stop();
        switch(li.innerHTML) {
          case "Help":
            this.toggleHelp();
            break;
          case "Preferences":
            this.togglePrefs();
            break;
          case "Connections":
            this.toggleConfig();
            break;
          case "Logout":
            window.location = "/logout";
            break;
          case "All tabs":
            this.clearSet(li);
            break;
          case "Edit":
            this.toggleTabsets();
            break;
        }

        if (this.tabsets[li.innerHTML]) {
          this.showSet(li.innerHTML);
        }
        $$('li.dropdown.open').invoke("removeClassName", "open");
      }
    }.bind(this));

    ['tab_menu_left', 'tab_menu_right'].each(function(side) {
      $(side).observe(click, function(e) {
        var li = e.findElement(".dropdown li");
        if (!li) return;

        if (li && li.getAttribute("rel")) {
          $(side).removeClassName("open");
          var win = this.getWindow(li.getAttribute("rel"));
          if (win) win.focus();
        }
      }.bind(this));
    }.bind(this));
  }

});
