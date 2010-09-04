var __bind = function(func, context) {
    return function(){ return func.apply(context, arguments); };
  };
Alice.Window = function(application, element, title, active, hashtag) {
  var orig_height;
  this.application = application;
  this.element = $(element);
  this.title = title;
  this.hashtag = hashtag;
  this.id = this.element.identify();
  this.active = active;
  this.input = new Alice.Input(this, this.id + "_msg");
  this.tab = $(this.id + "_tab");
  this.tabButton = $(this.id + "_tab_button");
  this.tabOverflowButton = $(this.id + "_tab_overflow_button");
  this.form = $(this.id + "_form");
  this.topic = $(this.id + "_topic");
  this.messages = this.element.down(".message_wrap");
  this.submit = $(this.id + "_submit");
  if (this.topic) {
    orig_height = this.topic.getStyle("height");
    this.topic.observe("click", __bind(function() {
      return this.topic.getStyle("height" === orig_height) ? this.topic.setStyle({
        height: "auto"
      }) : this.topic.setStyle({
        height: orig_height
      });
    }, this));
  }
  this.nicksVisible = false;
  this.visibleNick = "";
  this.visibleNickTimeout = "";
  this.nicks = [];
  this.messageLimit = 250;
  this.submit.observe("click", __bind(function(e) {
    this.input.send();
    return e.stop();
  }, this));
  this.tab.observe("mousedown", __bind(function(e) {
    if (!this.active) {
      this.focus();
      return (this.focusing = true);
    }
  }, this));
  this.tab.observe("click", __bind(function(e) {
    return (this.focusing = false);
  }, this));
  this.tabButton.observe("click", __bind(function(e) {
    if (this.active && !this.focusing) {
      return this.close();
    }
  }, this));
  this.messages.observe("mouseover", __bind(function(e) {
    return this.showNick(e);
  }, this));
  if (Prototype.Browser.Gecko) {
    this.resizeMessageArea();
    this.scrollToBottom();
  } else if (this.application.isMobile) {
    this.messageLimit = 50;
    this.messages.select("li").reverse().slice(50).invoke("remove");
  }
  if (this.active) {
    this.scrollToBottom(true);
  }
  this.makeTopicClickable();
  setTimeout(__bind(function() {
    var _a, _b, _c, _d, msg;
    _a = []; _c = this.messages.select("li.message div.msg");
    for (_b = 0, _d = _c.length; _b < _d; _b++) {
      msg = _c[_b];
      _a.push(msg.innerHTML = this.application.applyFilters(msg.innerHTML));
    }
    return _a;
  }, this), 1000);
  return this;
};
Alice.Window.prototype.isTabWrapped = function() {
  return this.tab.offsetTop > 0;
};
Alice.Window.prototype.unFocus = function() {
  this.active = false;
  this.input.uncancelNextFocus();
  this.element.removeClassName("active");
  this.tab.removeClassName("active");
  return (this.tabOverflowButton.selected = false);
};
Alice.Window.prototype.showNick = function(e) {
  var li, nick, stem, time;
  if (li = e.findElement("#" + (this.id) + " ul.messages li.message")) {
    if (this.nicksVisible || li === this.visibleNick) {
      return null;
    }
    clearTimeout(this.visisbleNickTimeout);
    this.visibleNick = li;
    nick = (time = "");
    if (li.hasClassName("consecutive")) {
      stem = li.previous("li:not(.consecutive)");
      if (!(stem)) {
        return null;
      }
      nick = stem.down(".nickhint");
      time = stem.down(".timehint");
    } else {
      nick = li.down(".nickhint");
      time = li.down(".timehint");
    }
    return nick || time ? (this.visibleNickTimeout = setTimeout(__bind(function(nick, time) {
      if (nick) {
        nick.style.opacity = 1;
        nick.style.webkitTransition = "opacity 0.1s ease-in-out";
      }
      if (time) {
        time.style.opacity = 1;
        time.style.webkitTransition = "opacity 0.1s ease-in-out";
      }
      return setTimeout(__bind(function() {
        if (this.nicksVisible) {
          return null;
        }
        if (nick) {
          nick.style.webkitTransition = "opacity 0.25s ease-in";
          nick.style.opacity = 0;
        }
        if (time) {
          time.style.webkitTransition = "opacity 0.25s ease-in";
          return (time.style.opacity = 0);
        }
      }, this));
    }, this))) : null;
  } else {
    this.visibleNick = "";
    return clearTimeout(this.visibleNickTimeout);
  }
};
Alice.Window.prototype.toggleNicks = function() {
  var _a, _b, _c, _d, _e, _f, _g, _h, opacity, span, transition;
  opacity = (typeof (_a = this.nicksVisible) !== "undefined" && _a !== null) ? _a : {
    0: 1
  };
  transition = (typeof (_b = this.nicksVisible) !== "undefined" && _b !== null) ? _b : {
    "ease-in": "ease-in-out"
  };
  _d = this.messages.select("span.nickhint");
  for (_c = 0, _e = _d.length; _c < _e; _c++) {
    span = _d[_c];
    span.style.webkitTransition = ("opacity 0.1s " + (transition));
    span.style.opacity = opacity;
  }
  _g = this.messages.select("div.timehint");
  for (_f = 0, _h = _g.length; _f < _h; _f++) {
    span = _g[_f];
    span.style.webkitTransition = ("opacity 0.1s " + (transition));
    span.style.opacity = opacity;
  }
  return (this.nicksVisible = !this.nicksVisible);
};
Alice.Window.prototype.focus = function(e) {
  document.title = this.title;
  this.application.previousFocus = this.application.activeWindow();
  this.application.windows().invoke("unFocus");
  this.active = true;
  this.tab.addClassName("active");
  this.element.addClassName("active");
  this.tabOverflowButton.selected = true;
  this.markRead();
  this.scrollToBottom(true);
  if (!(this.application.isMobile)) {
    this.input.focus();
  }
  if (Prototype.Browser.Gecko) {
    this.resizeMessageArea();
    this.scrollToBottom();
  }
  this.element.redraw();
  window.location.hash = this.hashtag;
  window.ocation = window.location.toString();
  return this.application.updateChannelSelect();
};
Alice.Window.prototype.markRead = function() {
  this.tab.removeClassName("unread");
  this.tab.removeClassName("highlight");
  return this.tabOverflowButton.removeClassName("unread");
};
Alice.Window.prototype.disable = function() {
  this.markRead();
  return this.tab.addClassName("disabled");
};
Alice.Window.prototype.enable = function() {
  return this.tab.removeClassName("disabled");
};
Alice.Window.prototype.close = function(e) {
  this.application.removeWindow(this);
  this.tab.remove();
  this.element.remove();
  return this.tabOverflowButton.remove();
};
Alice.Window.prototype.displayTopic = function(string) {
  this.topic.update(string);
  return this.makeTopicClickable();
};
Alice.Window.prototype.makeTopicClickable = function() {
  if (!(this.topic)) {
    return null;
  }
  return (this.topic.innerHTML = this.topic.innerHTML.replace(/(https?:\/\/[^\s]+)/ig, '<a href="$1" target="_blank" rel="noreferrer">$1</a>'));
};
Alice.Window.prototype.resizeMessageArea = function() {
  var bottom, top;
  top = this.messages.up().cumulativeOffset().top;
  bottom = this.input.element.getHeight() + 14;
  return this.messages.setStyle({
    position: "absolute",
    top: top + "px",
    bottom: bottom + "px",
    right: "0px",
    left: "0px",
    height: "auto"
  });
};
Alice.Window.prototype.showHappyAlert = function(message) {
  this.messages.down("ul").insert("<li class='event happynotice'><div class='msg'>" + (message) + "</div></li>");
  return this.scrollToBottom();
};
Alice.Window.prototype.showAlert = function(message) {
  this.messages.down("ul").insert("<li class='event notice'><div class='msg'>" + (message) + "</div></li>");
  return this.scrollToBottom();
};
Alice.Window.prototype.addMessage = function(message) {
  var _a, _b, _c, avatar, elem, listitems, msg, nick, prev, time;
  if (!(message.html)) {
    return null;
  }
  this.messages.down("ul").insert(message.html);
  if (message.consecutive) {
    prev = li.previous();
    if (prev && prev.hasClassName("avatar" && !prev.hasClassName("consecutive"))) {
      prev.down("div.msg").setStyle({
        minHeight: "0px"
      });
    }
    if (prev && prev.hasClassName("monospace")) {
      prev.down("div.msg").setStyle({
        paddingBottom: "0px"
      });
    }
  }
  if (message.event === "say") {
    msg = li.down("div.msg");
    msg.innerHTML = this.application.applyFilters(msg.innerHTML);
    if (this.nicksVisible) {
      if (nick = li.down("span.nickhint")) {
        nick.style.webkitTransition = "none 0 linear";
        nick.style.opacity = 1;
      }
      if (time = li.down("div.timehint")) {
        time.style.webkitTransition = "none 0 linear";
        nick.style.opacity = 1;
      }
    }
    if (message.consecutive && (avatar = li.previous(".avatar:not(.consecutive)"))) {
      avatar.down(".timehint").innerHTML = message.timestamp;
    }
  } else if (message.event === "topic") {
    displayTopic(message.body.escapeHTML());
  }
  if (!this.application.isFocused && message.highlight && message.window.title !== "info") {
    message.body = li.down(".msg").innerHTML.stripTags();
    Alice.growlNotify(message);
    this.application.addMissed();
  }
  if (message.nicks && message.nicks.length) {
    this.nicks = message.nicks;
  }
  if (this.element.hasClassName("active")) {
    this.scrollToBottom();
  } else if (this.title !== "info") {
    if (message.event === "say") {
      this.tab.addClassName("unread");
      this.tabOverflowButton.addClassName("unread");
      if (this.isTabWrapped()) {
        this.application.highlightChannelSelect;
      }
    }
    if (message.highlight) {
      this.tab.addClassName("highlight");
    }
  }
  listitems = this.messages.down("ul").childElements();
  if (listitems.length > this.messageLimit) {
    listitems.first().remove();
  }
  _b = li.select("span.timestamp");
  for (_a = 0, _c = _b.length; _a < _c; _a++) {
    elem = _b[_a];
    elem.innerHTML = Alice.epochToLocal(elem.innerHTML.strip(), this.application.options.timeformat);
    elem.style.opacity = 1;
  }
  return this.element.redraw();
};
Alice.Window.prototype.scrollToBottom = function(force) {
  var bottom, height, lastmsg, msgheight;
  bottom = (height = "");
  if (!force && (lastmsg = this.messages.down("ul.messages > li:last-child"))) {
    msgheight = lastmsg.offsetHeight;
    bottom = this.messages.scrollTop + this.messages.offsetHeight;
    height = this.messages.scrollHeight;
  }
  if (force || (bottom + msgheight + 100 >= height)) {
    this.messages.scrollTop = this.messages.scrollHeight;
    return this.element.redraw();
  }
};
Alice.Window.prototype.getNickNames = function() {
  return this.nicks;
};