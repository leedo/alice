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

    var regexes = {
      url: /\b(https?:\/\/(?:[^\s()<>]+|\(([^\s()<>]+|(\([^\s()<>]+\)))*\))+(?:\(([^\s()<>]+|(\([^\s()<>]+\)))*\)|[^\s`!()\[\]{};:'".,<>?«»“”‘’]))/g,
      twitter: /https?:\/\/(?:www\.)?twitter\.com\/(?:#!\/)?[^\/]+\/status\/(\d+)/i,
      img: /^http[^\s]*\.(?:jpe?g|gif|png|bmp|svg)[^\/]*$/i,
      audio: /^http[^\s]*\.(?:wav|mp3|ogg|aiff|m4a)[^\/]*$/i
    }
    

    alice.addFilters([
      function(msg, win) {
        msg.innerHTML = msg.innerHTML.replace(
          regexes.url, '<a href="$1" target="_blank" rel="noreferrer">$1</a>'
        );
      },
      function(msg, win) {
        msg.select("a").filter(function(a) {
          return regexes.audio.match(a.href);
        }).each(function(a) {
          var img = new Element("IMG", {"class": "audio", src: "/static/image/play.png"});
          img.onclick = function(){ Alice.playAudio(img) };
          a.insert({before: img})
        });
      },
      function (msg, win) {
        if (alice.options.images == "show") {
          msg.select("a").filter(function(a) {
            return regexes.twitter.match(a.href);
          }).each(function(a) {
            a.innerHTML = a.innerHTML.replace(re, "http://prettybrd.com/peebone/$1.png");
          });
        }
      },
      function (msg, win) {
        if (alice.options.images == "show") {
          msg.select("a").filter(function(a) {
            return regexes.img.match(a.innerHTML);
          }).each(function(a) {
            if(a.innerHTML.indexOf('nsfw') !== -1) return;
            var img = new Element("IMG", {src: alice.options.image_prefix + a.innerHTML});
            img.observe("load", function(){ Alice.loadInlineImage(img) });
            a.update(img);
            var div = new Element("DIV", {"class": "image"});
            a = a.replace(div);
            div.insert(a);
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
    ]);
  });
}
