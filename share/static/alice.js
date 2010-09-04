var Alice;
Alice = {};
if (window === window.parent) {
  document.observe("dom:loaded", function() {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l, _m, _n, _o, _p, _q, _r, alice, elem, js, kv, li, o, opt, options, orig_console, params;
    alice = new Alice.Application();
    window.alice = alice;
    options = {
      images: "show",
      avatars: "show",
      timeformat: "12"
    };
    js = /alice\.js\?(.*)?$/;
    _b = $$("script[src]").findAll(function(s) {
      return s.src.match(js);
    });
    for (_a = 0, _c = _b.length; _a < _c; _a++) {
      js = _b[_a];
      params = s.src.match(js)[1];
      _e = params.split("&");
      for (_d = 0, _f = _e.length; _d < _f; _d++) {
        o = _e[_d];
        kv = o.spit("=");
        options[kv[0]] = kv[1];
      }
    }
    alice.options = options;
    if (navigator.platform.match(/iphone/)) {
      alice.options.images = "hide";
    }
    orig_console;
    if (window.console) {
      orig_console = window.console;
      window.console = {};
    } else {
      window.console = {};
    }
    window.console.log = function() {
      var _g, _h, _i, _j, arg, win;
      win = alice.activeWindow();
      _g = []; _i = arguments;
      for (_h = 0, _j = _i.length; _h < _j; _h++) {
        arg = _i[_h];
        _g.push((function() {
          if (orig_console && orig_console.log) {
            orig_console.log(arg);
          }
          return win && options.debug === "true" ? win.addMessage({
            html: '<li class="message monospace"><div class="left">console</div><div class="msg">' + arguments[i].toString() + '</div></li>'
          }) : null;
        }).apply(this, arguments));
      }
      return _g;
    };
    _h = $$("ul.messages li.avatar:not(.consecutive) + li.consecutive");
    for (_g = 0, _i = _h.length; _g < _i; _g++) {
      li = _h[_g];
      li.previous().down("div.msg").setStyle({
        minHeight: "0px"
      });
    }
    _k = $$("ul.messages li.monospace + monospace.consecutive");
    for (_j = 0, _l = _k.length; _j < _l; _j++) {
      li = _k[_j];
      li.previous().down("div.msg").setStyle({
        paddingBottom: "0px"
      });
    }
    _n = $$("span.timestamp");
    for (_m = 0, _o = _n.length; _m < _o; _m++) {
      elem = _n[_m];
      if (elem.innerHTML) {
        elem.innerHTML = Alice.epochToLocal(elem.innerHTML.strip(), alice.options.timeformat);
        elem.style.opacity = 1;
      }
    }
    $("helpclose").observe("click", function() {
      return $("help").hide();
    });
    _q = $$("#config_overlay option");
    for (_p = 0, _r = _q.length; _p < _r; _p++) {
      opt = _q[_p];
      opt.selected = false;
    }
    $("tab_overflow_overlay").observe("change", function(e) {
      var win;
      return (win = alice.getWindow($("tab_overflow_overlay").value)) ? win.focus() : null;
    });
    $("config_overlay").observe("change", function(e) {
      var _s, _t, _u, _v, _w;
      if ((_s = $("config_overlay").value) === "Logs") {
        alice.toggleLogs(e);
      } else if (_s === "Connections") {
        alice.toggleConfig(e);
      } else if (_s === "Preferences") {
        alice.togglePrefs(e);
      } else if (_s === "Logout") {
        if (confirm("Logout?")) {
          window.location = "/logout";
        }
      } else if (_s === "Help") {
        alice.toggleHelp();
      }
      return (opt.selected = (function() {
        _t = []; _v = $$("#config_overlay option");
        for (_u = 0, _w = _v.length; _u < _w; _u++) {
          opt = _v[_u];
          _t.push(false);
        }
        return _t;
      })());
    });
    window.onkeydown = function(e) {
      var win;
      if (win = alice.activeWindow()) {
        if (Prototype.Browser.Gecko) {
          alice.activeWindow().resizeMessageArea();
        }
        return alice.activeWindow().scrollToBottom();
      }
    };
    window.onfocus = function() {
      var win;
      if (!(alice.isMobile)) {
        document.body.removeClassName("blurred");
      }
      if (win = alice.activeWindow()) {
        win.input.focus();
      }
      alice.isFocused = true;
      return alice.clearMissed();
    };
    window.status = " ";
    window.onblur = function() {
      if (!(alice.isMobile)) {
        document.body.addClassName("blurred");
      }
      return (alice.isFocused = false);
    };
    window.onhashchange = function() {
      return alice.focusHash();
    };
    window.onorientationchange = function() {
      return alice.activeWindow.scrollToBottom(true);
    };
    return alice.addFilers([
      function(content) {
        var filtered;
        filtered = content;
        filtered = filtered.replace(/(<a href=\"(:?.*?\.(:?wav|mp3|ogg|aiff|m4a))")/gi, "<img src=\"/static/image/play.png\" onclick=\"Alice.playAudio(this)\" class=\"audio\"/>$1");
        return filtered;
      }, function(content) {
        var filtered;
        filtered = content;
        if (alice.options.images === "show") {
          filtered = filtered.replace(/(<a[^>]*>)([^<]*\.(:?jpe?g|gif|png|bmp|svg)(:?\?v=0)?)</gi, "$1<img src=\"http:#i.usealice.org/$2\" onload=\"Alice.loadInlineImage(this)\" alt=\"Loading Image...\" title=\"$2\" style=\"display:none\"/><");
        }
        return filtered;
      }
    ]);
  });
}
