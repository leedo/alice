class Alice.Window
  constructor: (application, element, title, active, hashtag) ->
    @application = application

    @element = $ element
    @title = title
    @hashtag = hashtag
    @id = @element.identify()
    @active = active

    @input = new Alice.Input @, @id+"_msg"

    @tab = $ @id+"_tab"
    @tabButton = $ @id+"_tab_button"
    @tabOverflowButton = $ @id+"_tab_overflow_button"
    @form = $ @id+"_form"
    @topic = $ @id+"_topic"
    @messages = @element.down ".message_wrap"
    @submit = $ @id+"_submit"

    if @topic
      orig_height = @topic.getStyle "height"
     @topic.observe "click", =>
       if @topic.getStyle "height" == orig_height
         @topic.setStyle {height: "auto"}
       else
         @topic.setStyle {height: orig_height}

    @nicksVisible = false
    @visibleNick = ""
    @visibleNickTimeout = ""

    @nicks = []
    @messageLimit = 250

    @submit.observe "click", (e) =>
      @input.send()
      e.stop()

    @tab.observe "mousedown", (e) =>
      if not @active
        @focus()
        @focusing = true

    @tab.observe "click", (e) => @focusing = false

    @tabButton.observe "click", (e) => @close() if (@active and not @focusing)
    @messages.observe "mouseover", => @showNick()

    if Prototype.Browser.Gecko
      @resizeMessageArea()
      @scrollToBottom()
    else if @application.isMobile
      @messageLimit = 50
      @messages.select("li").reverse().slice(50).invoke "remove"

    @scrollToBottom(true) if @active
    @makeTopicClickable()

    setTimeout =>
      for msg in @messages.select("li.message div.msg")
        msg.innerHTML = @application.applyFilters msg.innerHTML
      , 1000

  isTabWrapped: ->
    @tab.offsetTop > 0

  unFocus: ->
    @active = false
    @input.uncancelNextFocus()
    @element.removeClassName "active"
    @tab.removeClassName "active"
    @tabOverflowButton.selected = false

  showNick: (e) ->
    if li = e.findElement "##{@id} ul.messages li.message"
      return if @nicksVisible or li == @visibleNick

      clearTimeout @visisbleNickTimeout

      @visibleNick = li

      nick, time
      if li.hasClassName "consecutive"
        stem = li.previous "li:not(.consecutive)"
        return unless stem

        nick = stem.down ".nickhint"
        time = stem.down ".timehint"
      else
        nick = li.down ".nickhint"
        time = li.down ".timehint"

      if nick or time
        @visibleNickTimeout = setTimeout (nick, time) =>
          if nick
            nick.style.opacity = 1
            nick.style.webkitTransition = "opacity 0.1s ease-in-out"
          if time
            time.style.opacity = 1
            time.style.webkitTransition = "opacity 0.1s ease-in-out"

          setTimeout =>
            return if @nicksVisible

            if nick
              nick.style.webkitTransition = "opacity 0.25s ease-in"
              nick.style.opacity = 0
            if time
              time.style.webkitTransition = "opacity 0.25s ease-in"
              time.style.opacity = 0
    else
      @visibleNick = ""
      clearTimeout @visibleNickTimeout

  toggleNicks: ->
    opacity = @nicksVisible ? 0 : 1
    transition = @nicksVisible ? "ease-in" : "ease-in-out"

    for span in @messages.select "span.nickhint"
      span.style.webkitTransition = "opacity 0.1s #{transition}"
      span.style.opacity = opacity
    for span in @messages.select "div.timehint"
      span.style.webkitTransition = "opacity 0.1s #{transition}"
      span.style.opacity = opacity

    @nicksVisible = !@nicksVisible

  focus: (e) ->
    document.title = @title
    @application.previousFocus = @application.activeWindow()
    @application.windows().invoke "unFocus"
    @active = true
    @tab.addClassName "active"
    @element.addClassName "active"
    @tabOverflowButton.selected = true
    @markRead()

    @scrollToBottom(true)

    @input.focus() unless @application.isMobile

    if Prototype.Browser.Gecko
      @resizeMessageArea()
      @scrollToBottom()

    @element.redraw()

    window.location.hash = @hashtag
    window.ocation = window.location.toString()

    @application.updateChannelSelect()

  markRead: ->
    @tab.removeClassName "unread"
    @tab.removeClassName "highlight"
    @tabOverflowButton.removeClassName "unread"

  disable: ->
    @markRead()
    @tab.addClassName "disabled"

  enable: -> @tab.removeClassName "disabled"

  close: (e) ->
    @application.removeWindow(@)
    @tab.remove()
    @element.remove()
    @tabOverflowButton.remove()

  displayTopic: (string) ->
    @topic.update(string)
    @makeTopicClickable()

  makeTopicClickable: ->
    return unless @topic

    @topic.innerHTML = topic.innerHTML.replace(
      /(https?:\/\/[^\s]+)/ig,
      '<a href="$1" target="_blank" rel="noreferrer">$1</a>')

  resizeMessageArea: ->
    top = @messages.up().cumulativeOffset().top
    bottom = @input.element.getHeight() + 14 # ew

    @messages.setStyle
      position: "absolute"
      top: top+"px"
      bottom: bottom+"px"
      right: "0px"
      left: "0px"
      height: "auto"

  showHappyAlert: (message) ->
    @messages.down("ul").insert "<li class='event happynotice'><div class='msg'>#{message}</div></li>"
    @scrollToBottom()

  showAlert: (message) ->
    @messages.down("ul").insert "<li class='event notice'><div class='msg'>#{message}</div></li>"
    @scrollToBottom()

  addMessage: (message) ->
    return unless message.html

    @messages.down("ul").insert message.html

    if message.consecutive
      prev = li.previous()
      if prev and prev.hasClassName "avatar" and !prev.hasClassName "consecutive"
        prev.down("div.msg").setStyle {minHeight: "0px"}
      if prev and prev.hasClassName "monospace"
        prev.down("div.msg").setStyle {paddingBottom: "0px"}

    if message.event == "say"
      msg = li.down "div.msg"
      msg.innerHTML = @application.applyFilters msg.innerHTML

      if @nicksVisible
        if nick = li.down "span.nickhint"
          nick.style.webkitTransition = "none 0 linear"
          nick.style.opacity = 1
        if time = li.down "div.timehint"
          time.style.webkitTransition = "none 0 linear"
          nick.style.opacity = 1

      if message.consecutive and avatar = li.previous ".avatar:not(.consecutive)"
        avatar.down(".timehint").innerHTML = message.timestamp

    else if message.event == "topic"
      displayTopic message.body.escapeHTML()

    if !@application.isFocused and message.highlight and message.window.title != "info"
      message.body = li.down(".msg").innerHTML.stripTags();
      Alice.growlNotify(message)
      @application.addMissed()

    if message.nicks and message.nicks.length
      @nicks = message.nicks

    if @element.hasClassName "active"
      @scrollToBottom()
    else if @title != "info"
      if message.event == "say"
        @tab.addClassName "unread"
        @tabOverflowButton.addClassName "unread"
        @application.highlightChannelSelect if @isTabWrapped()
      if message.highlight
        @tab.addClassName "highlight"

    listitems = @messages.down("ul").childElements()
    listitems.first().remove() if listitems.length > @messageLimit

    # fix timestamps
    for elem in li.select("span.timestamp")
      elem.innerHTML = Alice.epochToLocal elem.innerHTML.strip(), @application.options.timeformat
      elem.style.opacity = 1

    @element.redraw()

  scrollToBottom: (force) ->
    bottom, height

    if !force and lastmsg = @messages.down "ul.messages > li:last-child"
      msgheight = lastmsg.offsetHeight
      bottom = @messages.scrollTop + @messages.offsetHeight
      height = @messages.scrollHeight

    if force or bottom + msgheight + 100 >= height
      @messages.scrollTop = @messages.scrollHeight
      @element.redraw()

  getNickNames: -> @nicks
