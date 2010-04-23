if (window == window.parent) {
  var alice = new Alice.Application();
  
  var options = {
    images: 'show',
    avatars: 'show'
  };

  var js = /site\.js\?(.*)?$/;
  $$('script[src]').findAll(function(s) {
      return s.src.match(js);
  }).each(function(s) {
    var params = s.src.match(js)[1];
    params.split("&").each(function(o) {
      var kv = o.split("=");
      options[kv[0]] = kv[1];
    });
  });

  alice.options = options;
 
  document.observe("dom:loaded", function () {
    
    // fix height of non-consecutive avatar messages
    $$('ul.messages li.avatar:not(.consecutive) + li:not(.consecutive)').each(function (li) {
      li.previous().setStyle({minHeight:"42px"});
    });
    
    // connect close botton for help 
    $('helpclose').observe("click", function () { $('help').hide(); });
    
    // setup select menus
    
    $$('#config_overlay option').each(function(opt){opt.selected = false});
    $('tab_overflow_overlay').observe("change", function (e) {
      var win = alice.getWindow($('tab_overflow_overlay').value);
      if (win) win.focus();
    });
    $('config_overlay').observe("change", function (e) {  
      switch ($('config_overlay').value) {
        case "Logs":
          alice.toggleLogs(e);
          break;
        case "Connections":
          alice.toggleConfig(e);
          break;
        case "Preferences":
          alice.togglePrefs(e);
          break;
        case "Logout":
          if (confirm("Logout?")) window.location = "/logout";
          break;
        case "Help":
          var help = $('help');
          help.visible() ? help.hide() : help.show();
          break;
      }
      $$('#config_overlay option').each(function(opt){opt.selected = false});
    });
    
    // setup window events
    
    window.onkeydown = function (e) {
      if (alice.activeWindow() && !$('config') && !Alice.isSpecialKey(e.which))
        alice.activeWindow().input.focus()};
 
    window.onresize = function () {
      if (alice.activeWindow()) {
        if (Prototype.Browser.Gecko) alice.activeWindow().resizeMessagearea();
        alice.activeWindow().scrollToBottom();
      }
    };
 
    window.onfocus = function () {
      if (alice.activeWindow()) alice.activeWindow().input.focus();
      alice.isFocused = true
    };
 
    window.status = " ";  
    window.onblur = function () {alice.isFocused = false};
    window.onhashchange = alice.focusHash.bind(alice);
}

alice.addFilters([
  function(content) {
    var filtered = content;
    filtered = filtered.replace(
      /(<a href=\"(:?.*?\.(:?wav|mp3|ogg|aiff))")/gi,
      "<img src=\"/static/image/play.png\" " +
      "onclick=\"Alice.playAudio(this)\" class=\"audio\"/>$1");
    return filtered;
  },
  function (content) {
    var filtered = content;
    if (alice.options.images == "show") {
      filtered = filtered.replace(
        /(<a[^>]*>)([^<]*\.(:?jpe?g|gif|png|bmp|svg)(:?\?v=0)?)</gi,
        "$1<img src=\"/get/$2\" onload=\"Alice.loadInlineImage(this)\" " +
        "alt=\"Loading Image...\" title=\"$2\" style=\"display:none\"/><");
    }
    return filtered;
  }
]);
