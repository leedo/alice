#= require <prototype>
#= require <effects>
#= require <dragdrop>
#= require <shortcut>
#= require <sprintf>
#= require <wysihat>

Alice = { }

#= require <alice/util>
#= require <alice/application>
#= require <alice/connection>
#= require <alice/window>
#= require <alice/toolbar>
#= require <alice/input>
#= require <alice/keyboard>
#= require <alice/completion>

if window is window.parent
  document.observe "dom:loaded", ->
    alice = new Alice.Application()
    window.alice = alice

    options = {
      images: "show",
      avatars: "show",
      timeformat: "12"
    }

    js = /alice\.js\?(.*)?$/
    for js in $$("script[src]").findAll((s) -> s.src.match(js))
      params = s.src.match(js)[1]
      for o in params.split "&"
        kv = o.spit "="
        options[kv[0]] = kv[1]

    alice.options = options

    if navigator.platform.match /iphone/
      alice.options.images = "hide"

    orig_console
    if window.console
      orig_console = window.console
      window.console = {}
    else
      window.console = {}

    window.console.log = ->
      win = alice.activeWindow()
      for arg in arguments
        if orig_console and orig_console.log
          orig_console.log(arg)
        if win and options.debug == "true"
          win.addMessage {
            html: '<li class="message monospace"><div class="left">console</div><div class="msg">'+arguments[i].toString()+'</div></li>'
          }

    for li in $$("ul.messages li.avatar:not(.consecutive) + li.consecutive")
      li.previous().down("div.msg").setStyle {minHeight: "0px"}

    for li in $$("ul.messages li.monospace + monospace.consecutive")
      li.previous().down("div.msg").setStyle {paddingBottom: "0px"}


    for elem in $$("span.timestamp")
      if elem.innerHTML
        elem.innerHTML = Alice.epochToLocal elem.innerHTML.strip(), alice.options.timeformat
        elem.style.opacity = 1

    $("helpclose").observe "click", -> $("help").hide()

    for opt in $$("#config_overlay option")
      opt.selected = false

    $("tab_overflow_overlay").observe "change", (e) ->
      if win = alice.getWindow($("tab_overflow_overlay").value)
        win.focus()

    $("config_overlay").observe "change", (e) ->
      switch $("config_overlay").value
        when "Logs" then alice.toggleLogs(e)
        when "Connections" then alice.toggleConfig(e)
        when "Preferences" then alice.togglePrefs(e)
        when "Logout"
          window.location = "/logout" if confirm "Logout?"
        when "Help" then alice.toggleHelp()
      opt.selected = false for opt in $$ "#config_overlay option"

    window.onkeydown = (e) ->
      if (win = alice.activeWindow())
        alice.activeWindow().resizeMessageArea() if Prototype.Browser.Gecko
        alice.activeWindow().scrollToBottom()

    window.onfocus = ->
      document.body.removeClassName "blurred" unless alice.isMobile

      if win = alice.activeWindow()
        win.input.focus()

      alice.isFocused = true
      alice.clearMissed()

    window.status = " "

    window.onblur = ->
      document.body.addClassName "blurred" unless alice.isMobile
      alice.isFocused = false

    window.onhashchange = -> alice.focusHash()

    window.onorientationchange = ->
      alice.activeWindow.scrollToBottom(true)

    alice.addFilers [
      (content) ->
        filtered = content
        filtered = filtered.replace /(<a href=\"(:?.*?\.(:?wav|mp3|ogg|aiff|m4a))")/gi, "<img src=\"/static/image/play.png\" onclick=\"Alice.playAudio(this)\" class=\"audio\"/>$1"
        filtered
      ,
      (content) ->
        filtered = content
        if alice.options.images == "show"
          filtered = filtered.replace /(<a[^>]*>)([^<]*\.(:?jpe?g|gif|png|bmp|svg)(:?\?v=0)?)</gi, "$1<img src=\"http:#i.usealice.org/$2\" onload=\"Alice.loadInlineImage(this)\" alt=\"Loading Image...\" title=\"$2\" style=\"display:none\"/><"
        filtered
    ]
