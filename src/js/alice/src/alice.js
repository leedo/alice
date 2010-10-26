//= require <prototype>
//= require <effects>
//= require <dragdrop>
//= require <shortcut>
//= require <sprintf>
//= require <wysihat>

var Alice = { };

//= require <alice/util>
//= require <alice/application>
//= require <alice/connection>
//= require <alice/connection/websocket>
//= require <alice/connection/xhr>
//= require <alice/window>
//= require <alice/toolbar>
//= require <alice/input>
//= require <alice/keyboard>
//= require <alice/completion>

if (window == window.parent) {
  document.observe("dom:loaded", function () {
    var alice = new Alice.Application();
    window.alice = alice;

    // read in options from query string
    var options = {
      images: 'show',
      avatars: 'show',
      timeformat: '12' 
    };

    var js = /alice\.js\?(.*)?$/;
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

    // don't load images on the iphone
    if (navigator.platform.match(/iphone/i)) {
      alice.options.images = "hide";
    }

    // connect close botton for help 

    $('helpclose').observe("click", function () { $('help').hide(); });

    $$('li.dropdown').each(function (li) {
      li.observe("click", function (e) {
        var element = e.element();
        if (element.hasClassName("dropdown")) {
          if (li.hasClassName("open")) {
            li.removeClassName("open");
          }
          else {
            $$("li.dropdown").invoke("removeClassName", "open");
            li.addClassName("open");
          }
          e.stop();
        }
      });
    });

    document.observe("click", function (e) {
      $$('li.dropdown.open').invoke("removeClassName", "open");
    });


    // setup window events
    
    window.onkeydown = function (e) {
      if (!$('config') && !Alice.isSpecialKey(e.which))
        alice.input.focus();
    };
    
    window.onresize = function () {
      if (alice.activeWindow()) {
        if (Prototype.Browser.Gecko) alice.activeWindow().resizeMessagearea();
          alice.activeWindow().scrollToBottom();
      }
    };
    
    window.onfocus = function () {
      if (!alice.isMobile)
        window.document.body.removeClassName("blurred");

      alice.input.focus();

      alice.isFocused = true
      alice.clearMissed();
    };
    
    window.status = " ";  
    window.onblur = function () {
      if (!alice.isMobile)
        window.document.body.addClassName("blurred");
      alice.isFocused = false
    };
    window.onhashchange = function (e) {alice.focusHash()};

    window.onorientationchange = function() {
      alice.activeWindow().scrollToBottom(true);
    };

    // editing the copy buffer only seems to work with Safari on Mac

    if (Prototype.Browser.WebKit && !navigator.userAgent.match("Chrome")
        && navigator.platform.match("Mac")) {
      document.observe("copy", function(e) {
        if (e.findElement("ul.messages") && e.clipboardData) {
          var userSelection = window.getSelection();
          if (userSelection) {
            userSelection = String(userSelection);
            userSelection = userSelection.replace(/\n\s*\d+\:\d{2}[ap]?/g, "");
            userSelection = userSelection.replace(/\n\s*/g, "\n");
            userSelection = userSelection.replace(/>\s*\n([^<])/g, "> $1");
            userSelection = userSelection.replace(/\n([^<])/g, "\n<$1");

            e.preventDefault();
            e.clipboardData.setData("Text", userSelection);
          }
        }
      });
    }
    
    // setup default filters

    alice.addFilters([
      function(content) {
        var filtered = content;
        filtered = filtered.replace(
          /(<a href=\"(:?.*?\.(:?wav|mp3|ogg|aiff|m4a))")/gi,
          "<img src=\"/static/image/play.png\" " +
          "onclick=\"Alice.playAudio(this)\" class=\"audio\"/>$1");
        return filtered;
      },
      function (content) {
        var filtered = content;
        if (alice.options.images == "show") {
          filtered = filtered.replace(
            /(<a[^>]*>)([^<]*\.(:?jpe?g|gif|png|bmp|svg)(:?\?v=0)?)</gi,
            "$1<img src=\"http://i.usealice.org/$2\" onload=\"Alice.loadInlineImage(this)\" " +
            "alt=\"Loading Image...\" title=\"$2\" style=\"display:none\"/><");
        }
        return filtered;
      }
    ]);
  });
}
