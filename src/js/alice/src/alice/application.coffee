Alice.Application = Class.create
  initialize: ->
    @isFocused = true
    @window_map = new Hash
    @previousFocus = 0
    @connection = new Alice.Connection @
    @filters = []
    @keyboard = new Alice.Keyboard @
    @isPhone = (if window.navigator.platform.match(/(android|iphone)/i) then 1 else 0)
    @isMobile = @isPhone or Prototype.Browser.MobileSafari

    # Keep this as a timeout so the page doesn't show "loading..."
    window.onload = => setTimeout @connection.connect.bind(@connection), 1000
    
    # setup UI elements in initial state
    @makeSortable()

  actionHandlers:
    join: (action) ->
      win = @getWindow action['window'].id
      if not win
        @insertWindow action['window'].id, action.html
        win = new Alice.Window @, action['window'].id, action['window'].title, false, action['window'].hashtag
        @addWindow win
      else
        win.enable()
      win.nicks = action.nicks

    part: (action) -> @closeWindow(action['window'].id)

    nicks: (action) -> win.nicks = action.nicks if win = @getWindow action['window'].id

    alert: (action) -> @activeWindow().showAlert action['body']

    clear: (action) ->
      win = @getWindow action['window'].id
      if win
        win.messages.down("ul").update ""
        win.lastNick = ""

    connect: (action) ->
      win.enable() if (win = @getWindow win_info.id)? for win_info of action.windows
      Alice.connections.connectServer action.session if $ 'servers'

    disconnect: (action) ->
      for win_info of action.windows
        win = @getWindow win_info.id
        win.disable() if win
      Alice.connections.disconnectServer action.session if $ 'servers'

    focus: (action) ->
      return if not action.window_number
      if action.window_number == "next"
        @nextWindow()
      else if action.window_number.match /^prev/
        @previousWindow()
      else if action.window_number.match /^\d+$/
        tab = $('tabs').down 'li', action.window_number
        if tab
          window_id = tab.id.replace '_tab',''
          @getWindow(window_id).focus()
          
  toggleHelp: ->
    help = $ 'help'
    if help.visible() then help.hide() else help.show()

  toggleConfig: (e) ->
    @connection.getConfig (transport) =>
      alice.activeWindow().input.disabled = true
      $('container').insert transport.responseText
    e.stop()
  
  togglePrefs: (e) ->
    @connection.getPrefs (transport) =>
      alice.activeWindow().input.disabled = true
      $('container').insert transport.responseText
    e.stop()

  toggleLogs: (e) ->
    if @logWindow and not @logWindow.closed and @logWindow.focus
      @logWindow.focus()
    else
      @logWindow = window.open null, "logs", "resizable=no,scrollbars=no,statusbar=no, toolbar=no,location=no,width=500,height=480"
      @connection.getLog (transport)=>
        @logWindow.document.write transport.responseText
    e.stop()
  
  windows: -> @window_map.values()

  nth_window: (n) ->
    if tab = $('tabs').down 'li', n
      m = tab.id.match /([^_]+)_tab/
      @window_map.get m[1] if m

  openWindow: (element, title, active, hashtag) ->
    win = new Alice.Window @, element, title, active, hashtag
    @addWindow win
    win.focus() if active
    win
  
  addWindow: (win) ->
    @window_map.set win.id, win
    window.fluid.addDockMenuItem win.title, -> win.focus() if window.fluid

  removeWindow: (win) ->
    @focusLast() if win.active
    window.fluid.removeDockMenuItem win.title if window.fluid
    @previousFocus = 0 if win.id == this.previousFocus.id
    @window_map.unset win.id
    @connection.closeWindow win
    win = null
  
  getWindow: (windowId) -> @window_map.get windowId
  
  activeWindow: ->
    windows = @windows()
    for i in windows
      _w = windows[i]
      return _w if _w.active
    windows[0] if windows[0]
  
  addFilters: (list) -> @filters = @filters.concat list
  
  applyFilters: (content)-> @filters.inject content, (value,filter)-> filter value

  nextWindow: ->
    active = @activeWindow()
    nextTab = active.tab.next()
    nextTab = $$('ul#tabs li').first() unless nextTab
    return unless nextTab
    id = nextTab.id.replace '_tab',''
    this.getWindow(id).focus() unless id == active.id

  focusLast: ->
    if @previousFocus and @previousFocus.id != @activeWindow().id
      @previousFocus.focus()
    else
      @previousWindow()
  ###
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
      $('tab_overflow_overlay').insert(html.select);
      $(windowId+"_tab_overflow_button").selected = false;
      this.activeWindow().tabOverflowButton.selected = true;
      this.makeSortable();
    }
  },
  
  highlightChannelSelect: function() {
    $('tab_overflow_button').addClassName('unread');
  },
  
  unHighlightChannelSelect: function() {
    $('tab_overflow_button').removeClassName('unread');
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
  }
});
###