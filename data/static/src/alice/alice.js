//= require <prototype>
//= require <scriptaculous>
//= require <scriptaculous/effects>
//= require <scriptaculous/controls>
//= require <scriptaculous/dragdrop>

var Alice = Class.create({
  initialize: function () {
    this.isCtrl = false;
    this.isCommand = false;
    this.isAlt = false;
    this.isFocused = true;
    this.windows = new Hash();
    this.previousFocus = 0;
    this.connection = new Alice.Connection;
    this.filters = [ this.linkFilter ];
    this.monospaceNicks = ['Shaniqua', 'root', 'p6eval'];
    document.onkeyup = this.onKeyUp.bind(this);
    document.onkeydown = this.onKeyDown.bind(this);
    setTimeout(this.connection.connect.bind(this.connection), 1000);
  },
  
  toggleConfig: function (e) {
    if (! $('config')) {
      this.connection.getConfig(function (transport) {
          $('container').insert(transport.responseText);
        });
    }
    else {
      $('config').remove();
      $$('.overlay').invoke('remove');
    }
  },
  
  submitConfig: function(form) {
    $$('#config .channelselect').each(function (select) {
      $A(select.options).each(function (option) {
        option.selected = true;
      });
    });
    this.connection.sendConfig(form.serialize());
    $('config').remove();
    $$('.overlay').invoke('remove');
    return false;
  },
  
  addWindow: function (win) {
    this.windows.set(win.id, win);
  },
  
  removeWindow: function (win) {
    if (win.active) this.focusLast();
    this.windows.unset(win.id);
    this.connection.closeWindow(win);
    win = null;
  },
  
  getWindow: function (windowId) {
    return this.windows.get(windowId);
  },
  
  activeWindow: function () {
    var windows = this.windows.values();
    for (var i=0; i < windows.length; i++) {
      if (windows[i].active) return windows[i];
    }
    if (windows[0]) return windows[0];
  },
  
  onKeyUp: function (e) {
    if (e.which != 75 && e.which != 78 && e.which != 80) {
      this.isCtrl = false;
      this.isCommand = false;
      this.isAlt = false; 
    }
  },
  
  onKeyDown: function (e) {
    if (e.which == 17)
      this.isCtrl = true;
    else if (e.which == 91)
      this.isCommand = true;
    else if (e.which == 18)
      this.isAlt = true;
    else if (this.isCtrl && e.which == 75) {
      this.activeWindow().messages.innerHTML = '';
      return false;
    }
    else if (this.isCtrl && e.which == 78) {
      this.nextWindow();
      return false;
    }
    else if (this.isCtrl && e.which == 80) {
      this.previousWindow();
      return false;
    }
    else if (e.which == Event.KEY_UP) {
      this.activeWindow().previousMessage();
    }
    else if (e.which == Event.KEY_DOWN) {
      this.activeWindow().nextMessage();
    }
  },
  
  linkFilter: function (content) {
    var filtered = content;
    filtered = filtered.replace(
      /(https?\:\/\/[\w\d$\-_.+!*'(),%\/?=&;~#:@]*)/gi,
      "<a href=\"$1\">$1</a>");
    return filtered;
  },
  
  addFilters: function (list) {
    this.filters = this.filters.concat(list);
  },
  
  applyFilters: function (content) {
    this.filters.each(function(filter) {
        content = filter(content);
      });
    return content;
  },
  
  nextWindow: function () {
    var nextWindow = this.activeWindow().tab.next();
    if (! nextWindow)
      nextWindow = $$('.window').first();
    if (! nextWindow) return;
    nextWindow = nextWindow.id.replace('_tab','');
    this.getWindow(nextWindow).focus();
  },
  
  focusLast: function () {
    if (this.previousFocus)
      this.previousFocus.focus();
    else if (this.windows.values().length)
      this.windows.values().first().focus();
  },
  
  previousWindow: function () {
    var prevWindow = this.activeWindow().tab.previous();
    if (! prevWindow)
      prevWindow = $$('.window').last();
    if (! prevWindow) return;
    prevWindow = prevWindow.id.replace('_tab','');
    this.getWindow(prevWindow).focus();
  },
  
  closeWindow: function (windowId) {
    var win= this.getWindow(windowId);
    if (win) win.close();
  },
  
  insertWindow: function (windowId, html) {
    if (! $(windowId)) {
      $('windows').insert(html['window']);
      $('tabs').insert(html.tab);
      makeSortable();
    }
  },
  
  handleActions: function (list) {
    var self = this;
    list.each(function(action) {
      self.handleAction(action);
    });
  },
  
  handleAction: function (action) {
    switch (action.event) {
      case "join":
        this.insertWindow(action['window'].id, action.html);
        break;
      case "part":
        this.closeWindow(action['window'].id);
        break;
    }
  },
  
  displayMessages: function (list) {
    var self = this;
    list.each(function(message) {
      self.displayMessage(message);
    });
  },
  
  displayMessage: function (message) {
    var win = alice.getWindow(message['window'].id);
    if (! win) {
      this.connection.requestWindow(
        message['window'].title, message['window'].session, message);
      return;
    }
    win.addMessage(message);
  }
});

//= require <alice/window>
//= require <alice/connection>
//= require <alice/autocompleter>
//= require <alice/util>

var alice = new Alice();

document.observe("dom:loaded", function () {
  $$("div.topic").each(function (topic){
    topic.innerHTML = alice.linkFilter(topic.innerHTML)});
  $('config_button').observe("click", alice.toggleConfig.bind(alice));
  alice.activeWindow().input.focus()
  window.onkeydown = function () {
    if (! $('config') && ! alice.isCtrl && ! alice.isCommand && ! alice.isAlt)
      alice.activeWindow().input.focus()};
  window.onresize = function () {
    alice.activeWindow().scrollToBottom()};
  window.status = " ";  
  window.onfocus = function () {
    alice.activeWindow().input.focus();
    alice.isFocused = true};
  window.onblur = function () {alice.isFocused = false};
  makeSortable();
});
