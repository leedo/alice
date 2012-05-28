if (window == window.parent) {
  document.observe("dom:loaded", function () {
    var alice = new Alice.Application();
    window.alice = alice;

    // connect close botton for help 
    $('helpclose').observe("click", function () { $('help').hide(); });
    $('nicklist_toggle').observe("click", function () { alice.toggleNicklist() });
   
    $$('.dropdown').each(function (menu) {
      menu.observe(alice.supportsTouch ? "touchstart" : "mousedown", function (e) {
        e.stop();
        var element = e.element('.dropdown');
        if (element.hasClassName("dropdown")) {
          if (menu.hasClassName("open")) {
            menu.removeClassName("open");
          }
          else {
            $$(".dropdown.open").invoke("removeClassName", "open");
            menu.addClassName("open");
          }
        }
      });
    });

    document.observe(alice.supportsTouch ? "touchend" : "mouseup", function (e) {
      if (e.findElement('.dropdown')) return;
      $$('.dropdown.open').invoke("removeClassName", "open");
    });

    // setup window events
    
    if (alice.isMobile) {
      $('nicklist_toggle').addClassName('visible');
    }
    else {
      window.onkeydown = function (e) {
        if (!alice.input.disabled && !Alice.isSpecialKey(e.which))
          alice.input.focus();
      };


      var windows = $('windows');
      var toggle = $('nicklist_toggle');

      var resize = function () {
        var active = alice.activeWindow();
        var position = active.captureScrollPosition();

        var end = function(){
          alice.freeze();
          alice.tabs_width = $('tabs_container').getWidth();
          alice.updateOverflowMenus();
          active.scrollToPosition(position);
          active.shiftTab();
          window.onresize = resize;
        };

        var end_timer;

        window.onresize = function() {
          clearTimeout(end_timer);
          end_timer = setTimeout(end, 1000);
        };
      };

      window.onresize = resize;

      var move = function(e) {
        var width = document.viewport.getWidth();
        var left = windows.hasClassName('nicklist') ? 200 : 100;
        var visible  = toggle.hasClassName('visible');
        if (!visible && width - e.pointerX() > left)
          return;

        toggle.addClassName('visible');

        var end = function() {
          toggle.removeClassName('visible');
          window.onmousemove = move;
        };
        var end_timer;

        window.onmousemove = function() {
          clearTimeout(end_timer);
          end_timer = setTimeout(end, 1000);
        };
      };

      window.onmousemove = move;

      window.onfocus = function () {
        alice.input.focus();

        alice.freeze();
        alice.tabs_width = $('tabs_container').getWidth();
        alice.updateOverflowMenus();

        alice.isFocused = true
        alice.clearMissed();
      };

      window.status = " ";  
      window.onblur = function () {
        alice.isFocused = false
      };
    }

    window.onhashchange = function (e) {alice.focusHash()};

    window.onorientationchange = function() {
      var active = alice.activeWindow();
      active.scrollToPosition(0);
      alice.freeze();
      active.shiftTab();
    };

    document.observe("copy", function(e) {
      if (!e.findElement("ul.messages")) return;

      if(!Prototype.Browser.IE && typeof window.getSelection !== 'undefined') {
        var buffer = new Element("DIV", {"class": "copybuffer"});
        document.getElementsByTagName("body")[0].appendChild(buffer);
        var sel = window.getSelection();
        var range = sel.getRangeAt(0);
        buffer.appendChild(range.cloneContents());
        Alice.cleanupCopy(buffer);
        sel.selectAllChildren(buffer);

        setTimeout(function() {
          if(typeof window.getSelection().setBaseAndExtent !== 'undefined') {
            sel.setBaseAndExtent(
              range.startContainer,
              range.startOffset,
              range.endContainer,
              range.endOffset
            );
          }
        }, 0);

      }
    });

    // no filters for phones
    if (alice.isMobile) return;

    alice.addFilters([
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
          var matches = msg.select("a").inject(0, function(acc, a) {
            var oembed = alice.oembeds.find(function(service) {
              return service.match(a.href);
            });
            if (oembed) {
              alice.embed(a, win);
              acc++;
            }
            return acc;
          });
          return matches > 0;
        }
      },
      function (msg, win) {
        msg.select("a").filter(function(a) {
          var img = a.readAttribute("img") || a.innerHTML;
          return img.match(Alice.RE.img);
        }).each(function(a) {
          var image = a.readAttribute("img") || a.href;
          if (alice.options.images == "show" && !image.match(/#(nsfw|hide)$/))
            win.inlineImage(a);
          else
            a.observe("click", function(e){e.stop();win.inlineImage(a)});
        });
      }
    ]);

    // work around chrome bugs! what the fuck.
    if (window.navigator.userAgent.match(/chrome/i)) {
      alice.addFilters([
        function(msg, win) {
          msg.setStyle({borderWidthTop: "1px"});
        }
      ]);
    }
  });

  setInterval(function(){new Ajax.Request("/say")}, 1000 * 60 * 5);
}
