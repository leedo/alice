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
    @isJankyScroll = Prototype.Browser.Gecko || Prototype.Browser.IE

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

  nextUnreadWindow: ->
    active = @activeWindow()
    tabs = active.tab.nextSiblings().concat active.tab.previousSiblings().reverse()
    unread = tabs.find (tab)-> tab.hasClassName "unread"
    if unread
      id = unread.id.replace "_tab", ""
      this.getWindow(id).focus() if id

  focusLast: ->
    if @previousFocus and @previousFocus.id is !@activeWindow().id
      @previousFocus.focus()
    else
      @previousWindow()

  previousWindow: ->
    active = @activeWindow()
    previousTab = @activeWindow().tab.previous();
    previousTab = $$('ul#tabs li').last() unless previousTab
    return unless previousTab
    id = previousTab.id.replace '_tab',''
    @getWindow(id).focus() unless id is active.id

  closeWindow: (windowId) -> win.close() if win = @getWindow windowId
  
  insertWindow: (windowId, html) ->
    if !$ windowId
      $('windows').insert html['window']
      $('tabs').insert html.tab
      $('tab_overflow_overlay').insert html.select
      $(windowId+"_tab_overflow_button").selected = false
      this.activeWindow().tabOverflowButton.selected = true
      this.makeSortable()

  highlightChannelSelect: -> $('tab_overflow_button').addClassName 'unread'
  
  unHighlightChannelSelect: -> $('tab_overflow_button').removeClassName 'unread'
  
  updateChannelSelect: ->
    windows = @windows()
    for i in windows
      win = windows[i]
      if (win.tab.hasClassName 'unread' or win.tab.hasClassName 'highlight') and win.isTabWrapped()
        return @highlightChannelSelect()
    @unHighlightChannelSelect()
  
  handleAction: (action) -> @actionHandlers[action.event].call @, action if @actionHandlers[action.event]

  displayMessage: (message) ->
    win = @getWindow message['window'].id
    if win
      win.addMessage(message);
    else
      @connection.requestWindow message['window'].title, message['window'].id, message
  
  focusHash: (hash) ->
    hash = window.location.hash if not hash 
    if hash
      hash = decodeURIComponent hash
      hash = hash.replace /^#/, ""
      windows = @windows()
      for win in windows
        if win.hashtag == hash
          win.focus() if win and not win.active
          return

  makeSortable: ->
    Sortable.create 'tabs',
      overlap: 'horizontal'
      constraint: 'horizontal'
      format: /(.+)/
      onUpdate: (res) =>
        vtabs = res.childElements()
        order = tabs.collect (t)->
          m = t.id.match /([^_]+)_tab/
          return m[1] if m 
        this.connection.sendTabOrder order if order.length

  addMissed: ->
    unless window.fluid
      if window.fluid.dockBadge
        window.fluid.dockBadge++
      else
        window.fluid.dockBadge = 1

  clearMissed: ->
    unless window.fluid
      window.fluid.dockBadge = ""