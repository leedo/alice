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

    // connect close botton for help 
    $('helpclose').observe("click", function () { $('help').hide(); });
    $('nicklist_toggle').observe("click", function () { alice.toggleNicklist() });

    $$('.dropdown').each(function (menu) {
      menu.observe(alice.supportsTouch ? "touchstart" : "mousedown", function (e) {
        var element = e.element('.dropdown');
        if (element.hasClassName("dropdown")) {
          if (menu.hasClassName("open")) {
            menu.removeClassName("open");
          }
          else {
            $$(".dropdown.open").invoke("removeClassName", "open");
            menu.addClassName("open");
          }
          e.stop();
        }
      });
    });

    document.observe(alice.supportsTouch ? "touchend" : "mouseup", function (e) {
      if (e.findElement('.dropdown')) return;
      $$('.dropdown.open').invoke("removeClassName", "open");
    });

    // setup window events
    
    window.onkeydown = function (e) {
      if (!$('config') && !Alice.isSpecialKey(e.which))
        alice.input.focus();
    };
    

    var scroll = false;

    var complete = function(){
      $('windows').removeClassName("resizing");
      var active = alice.activeWindow();
      if (scroll) active.scrollToBottom(true);
      active.shiftTab();
      scroll = false;
      Event.observe(window, "resize", resize);
    };

    var resize = function () {
      Event.stopObserving(window, "resize");
      $('windows').addClassName("resizing");
      scroll = alice.activeWindow().shouldScrollToBottom();
      setTimeout(complete, 2000);
    };

    Event.observe(window, "resize", resize);

    window.onfocus = function () {
      alice.input.focus();

      alice.isFocused = true
      alice.clearMissed();
    };
    
    window.status = " ";  
    window.onblur = function () {
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
      function(msg, win) {
        if (win.type == "info") return;
        msg.innerHTML = msg.innerHTML.replace(
          Alice.RE.channel, '$1<a class="channel" href="javascript:alice.connection.sendMessage({msg: \'/join $2\', source: \'' + win.id + '\'})">$2</a>'
        );
      },
      function(msg, win) {
        msg.select("a").filter(function(a) {
          return Alice.RE.audio.match(a.href);
        }).each(function(a) {
          var img = new Element("IMG", {"class": "audio", src: "/static/image/play.png"});
          img.onclick = function(){ Alice.playAudio(img) };
          a.insert({before: img})
        });
      },
      function (msg, win) {
        if (alice.options.images == "show") {
          msg.select("a").filter(function(a) {
            return Alice.RE.twitter.match(a.href);
          }).each(function(a) {
            a.innerHTML = a.innerHTML.replace(Alice.RE.twitter, "http://prettybrd.com/peebone/$1.png");
          });
        }
      },
      function (msg, win) {
        msg.select("a").filter(function(a) {
          return Alice.RE.img.match(a.innerHTML);
        }).each(function(a) {
          if (alice.options.images == "show")
            win.inlineImage(a);
          else
            a.observe("click", function(e){e.stop();win.inlineImage(a)});
        });
      },
      function (msg, win) {
        if (alice.options.images == "show") {
          msg.select("a").filter(function(a) {
            return Alice.RE.gist.match(a.href);
          }).each(function(a) {
            var iframe = new Element('iframe', {src: a.href+".pibb"});
            iframe.setStyle({width: (msg.getWidth() - 50)+"px"});
            var data = {
              provider_name: "gist.github.org",
              title: a.href.match(/[^\/]*$/),
              type: "rich",
              html: iframe
            };
            alice.insertOembedContent(a, data, win);
          });
        }
      },
      function (msg, win) {
        if (alice.options.images == "show") {
          msg.select("a").each(function(a) {
            var oembed = alice.oembeds.find(function(service) {
              return service[0].match(a.href);
            });
            if (oembed) {
              var callback = alice.addOembedCallback(a.identify(), win);
              var params = {
                url: a.href,
                format: 'json',
                callback: callback
              };
              var src = (oembed[1] || "http://oohembed.com/oohembed/")+ "?"+Object.toQueryString(params);
              var script = new Element('script', {src: src});
              a.insert(script);
            }
          })
        }
      },

      // work around chrome bugs! what the fuck.
      function(msg, win) {
        if (window.navigator.userAgent.match(/chrome/i)) {
          msg.setStyle({borderWidthTop: "1px"});
        }
      }

    ]);
  });
}
