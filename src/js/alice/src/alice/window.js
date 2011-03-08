Alice.Window = Class.create({
  initialize: function(application, serialized) {
    this.application = application;
    
    this.element = $(serialized['id']);
    this.title = serialized['title'];
    this.type = serialized['type'];
    this.hashtag = serialized['hashtag'];
    this.id = this.element.identify();
    this.active = false;
    this.topic = serialized['topic'];
    this.tab = $(this.id + "_tab");
    this.tabButton = $(this.id + "_tab_button");
    this.tabOverflowButton = $(this.id + "_tab_overflow");
    this.messages = this.element.down('.messages');
    this.nicksVisible = false;
    this.visibleNick = "";
    this.visibleNickTimeout = "";
    this.nicks = [];
    this.messageLimit = this.application.isMobile ? 50 : 200;
    this.msgid = 0;
    this.visible = true;
    this.lastnotify = 0;
    
    this.setupEvents();
  },

  hide: function() {
    this.tabOverflowButton.hide();
    this.element.hide();
    this.tab.addClassName('hidden');
    this.tab.removeClassName('visible');
    this.visible = false;
  },

  show: function() {
    this.tabOverflowButton.show();
    this.element.show();
    this.tab.addClassName('visible');
    this.tab.removeClassName('hidden');
    this.visible = true;
  },

  setupEvents: function() {
    this.application.supportsTouch ? this.setupTouchEvents() : this.setupMouseEvents();
  },

  setupTouchEvents: function() {
    this.messages.observe("touchstart", function (e) {
      this.showNick(e);
    }.bind(this));
    this.tab.observe("touchstart", function (e) {
      e.stop();
      if (!this.active) this.focus();
    }.bind(this));
    this.tabButton.observe("touchstart", function(e) {
      if (this.active) {
        e.stop();
        confirm("Are you sure you want to close this tab?") && this.close()
      }
    }.bind(this));
  },

  setupMouseEvents: function() {
    // huge mess of click logic to get the right behavior.
    // (e.g. clicking on unfocused (x) button does not close tab)
    this.tab.observe("mousedown", function(e) {
      if (!this.active) {this.focus(); this.focusing = true}
    }.bind(this));

    this.tab.observe("click", function(e) {this.focusing = false}.bind(this));

    this.tabButton.observe("click", function(e) {
      if (this.active && !this.focusing) 
        if (!this.application.isPhone || confirm("Are you sure you want to close this tab?"))
          this.close()
    }.bind(this));

    this.messages.observe("mouseover", this.showNick.bind(this));
  },

  setupMessages: function() {
    // fix height of non-consecutive avatar messages
    this.messages.select('li.avatar:not(.consecutive) + li.consecutive').each(function (li) {
      li.previous().down('div.msg').setStyle({minHeight:'0px'});
    });

    this.messages.select('li.monospaced + li.monospaced.consecutive').each(function(li) {
      li.previous().down('div.msg').setStyle({paddingBottom:'0px'});
    });

    // change timestamps from epoch to local time
    this.messages.select('span.timestamp').each(function(elem) {
      var inner = elem.innerHTML.strip();
      if (inner.match(/^\d+$/)) {
        elem.innerHTML = Alice.epochToLocal(inner, alice.options.timeformat);
        elem.style.opacity = 1;
      }
    });

    this.scrollToBottom(true);

    // wait a second to load images, otherwise the browser will say "loading..."
    setTimeout(function () {
      this.messages.select('li.message div.msg').each(function (msg) {
        this.application.applyFilters(msg, this);
      }.bind(this));
    }.bind(this), this.application.loadDelay);

    var last = this.messages.down("li:last-child");
    if (last && last.id) {
      this.application.log("setting "+this.title+" msgid to "+last.id);
      this.msgid = last.id.replace("msg-", "");
    }
  },
  
  isTabWrapped: function() {
    return this.tab.offsetTop > 0;
  },
  
  unFocus: function() {
    this.active = false;
    this.element.removeClassName('active');
    this.tab.removeClassName('active');
    this.tabOverflowButton.selected = false;
    this.addFold();
  },

  addFold: function() {
    this.messages.select("li.fold").invoke("removeClassName", "fold");
    var last = this.messages.childElements().last();
    if (last) last.addClassName("fold");
  },

  showNick: function (e) {
    var li = e.findElement("li.message");
    if (li) {
      if (this.nicksVisible || li == this.visibleNick) return;
      clearTimeout(this.visibleNickTimeout);

      this.visibleNick = li;
      var nick; var time;
      if (li.hasClassName("consecutive")) {
        var stem = li.previous("li:not(.consecutive)");
        if (!stem) return;
        if (li.hasClassName("avatar")) nick = stem.down("span.nick");
        time = stem.down(".timehint");
      } else {
        if (li.hasClassName("avatar")) nick = li.down("span.nick");
        time = li.down(".timehint");
      }

      if (nick || time) {
        this.visibleNickTimeout = setTimeout(function(nick, time) {
          if (nick) nick.style.opacity = 1;
          if (time) time.style.opacity = 1;

          setTimeout(function(){
            if (this.nicksVisible) return;
            if (nick) nick.style.opacity = 0;
            if (time) time.style.opacity = 0;
          }.bind(this, nick, time) , 1000);
        }.bind(this, nick, time), 500);
      }
    }
    else {
      this.visibleNick = "";
      clearTimeout(this.visibleNickTimeout);
    }
  },
  
  toggleNicks: function () {
    if (this.nicksVisible) {
      this.messages.select("li.avatar span.nick").each(function(span){
        span.style.opacity = 0;
      });
      this.messages.select("div.timehint").each(function(span){
        span.style.opacity = 0;
      });
    }
    else {
      this.messages.select("li.avatar span.nick").each(function(span){
        span.style.opacity = 1;
      });
      this.messages.select("div.timehint").each(function(span){
        span.style.opacity = 1;
      });
    }
    this.nicksVisible = !this.nicksVisible;
  },

  focus: function(event) {
    if (!this.application.currentSetContains(this)) return;

    this.element.addClassName('active');
    this.tab.addClassName('active');
    this.scrollToBottom(true);

    this.application.previousFocus = this.application.activeWindow();
    if (this != this.application.previousFocus)
      this.application.previousFocus.unFocus();

    this.active = true;

    this.application.setSource(this.id);
    this.application.displayNicks(this.nicks);
    this.markRead();
    this.setWindowHash();
    this.application.updateChannelSelect();

    // remove fold class from last message
    var last = this.messages.childElements().last();
    if (last && last.hasClassName("fold"))
      last.removeClassName("fold");

    this.application.displayTopic(this.topic);
    document.title = this.title;

    return this;
  },

  setWindowHash: function () {
    var new_hash = this.application.selectedSet + this.hashtag;
    if (new_hash != window.location.hash) {
      window.location.hash = encodeURI(new_hash);
      window.location = window.location.toString();
    }
  },
  
  markRead: function () {
    this.tab.removeClassName("unread");
    this.tab.removeClassName("highlight");
    this.tabOverflowButton.removeClassName("unread");
  },
  
  disable: function () {
    this.markRead();
    this.tab.addClassName('disabled');
  },
  
  enable: function () {
    this.tab.removeClassName('disabled');
  },
  
  close: function(event) {
    this.application.removeWindow(this);
    this.tab.remove();
    this.element.remove();
    this.tabOverflowButton.remove();
  },
  
  showHappyAlert: function (message) {
    this.messages.insert(
      "<li class='event happynotice'><div class='msg'>"+message+"</div></li>"
    );
    this.scrollToBottom();
  },
  
  showAlert: function (message) {
    this.messages.insert(
      "<li class='event notice'><div class='msg'>"+message+"</div></li>"
    );
    this.scrollToBottom();
  },

  announce: function (message) {
    this.messages.insert(
      "<li class='message announce'><div class='msg'>"+message+"</div></li>"
    );
    this.scrollToBottom();
  },

  trimMessages: function() {
    this.messages.select("li").reverse().slice(this.messageLimit).invoke("remove");
  },

  addChunk: function(chunk) {
    this.messages.insert({bottom: chunk.html});
    this.trimMessages();
    this.setupMessages();
    if (chunk.nicks && chunk.nicks.length)
      this.updateNicks(chunk.nicks);
    this.element.scrollTop = this.messages.scrollHeight;
  },

  addMessage: function(message) {
    if (!message.html || message.msgid <= this.msgid) return;
    
    this.messages.insert(message.html);
    if (message.msgid) this.msgid = message.msgid;
    this.trimMessages();

    //this.messages.down('ul').insert(Alice.uncacheGravatar(message.html));
    var li = this.messages.down('li:last-child');

    if (message.consecutive) {
      var prev = li.previous(); 
      if (prev && prev.hasClassName("avatar") && !prev.hasClassName("consecutive")) {
        prev.down('div.msg').setStyle({minHeight: '0px'});
      }
      if (prev && prev.hasClassName("monospaced")) {
        prev.down('div.msg').setStyle({paddingBottom: '0px'});
      }
    }
    
    if (message.event == "say") {
      var msg = li.down('div.msg');
      this.application.applyFilters(msg, this);
      
      var nick = li.down('span.nick');
      if (nick && this.nicksVisible) nick.style.opacity = 1;

      var time = li.down('div.timehint');
      if (time && this.nicksVisible) time.style.opacity = 1;
      
      if (message.consecutive) {
        var avatar = li.previous(".avatar:not(.consecutive)");
        if (avatar && avatar.down(".timehint"))
          avatar.down(".timehint").innerHTML = message.timestamp;
      }
    }
    else if (message.event == "topic") {
      this.topic = message.body;
      if (this.active) this.application.displayTopic(this.topic);
    }
    
    if (!this.application.isFocused && !message.self &&
        (message.highlight || this.type == "privmsg") ) {
      message.body = li.down(".msg").innerHTML.stripTags();
      var time = (new Date()).getTime();
      if (time - this.lastnotify > 5000) {
        this.lastnotify = time;
        Alice.growlNotify(message);
      }
      this.application.addMissed();
    }
    
    if (message.nicks && message.nicks.length)
      this.updateNicks(message.nicks);
    
    this.scrollToBottom();

    // highlight the tab
    if (!this.active && this.title != "info") {
      var wrapped = this.isTabWrapped();
      if (message.event == "say" && !message.self) {
        this.tab.addClassName("unread");
        this.tabOverflowButton.addClassName("unread");
        if (wrapped) this.application.highlightChannelSelect("unread");
      }
      if (message.highlight) {
        this.tab.addClassName("highlight");
        if (wrapped) this.application.highlightChannelSelect("highlight");
      }
      if (message.window.type == "privmsg" && wrapped) {
        this.application.highlightChannelSelect("highlight");
      }
    }

    // fix timestamps
    li.select("span.timestamp").each(function(elem) {
      elem.innerHTML = Alice.epochToLocal(elem.innerHTML.strip(), this.application.options.timeformat);
      elem.style.opacity = 1;
    }.bind(this));

    this.element.redraw();
  },

  shouldScrollToBottom: function() {
    var lastmsg = this.messages.down('li:last-child');
    if (!lastmsg) return false;

    var msgheight = lastmsg.offsetHeight;
    var bottom = this.element.scrollTop + this.element.offsetHeight;
    var height = this.element.scrollHeight;

    return bottom + msgheight + 100 >= height;
  },
  
  scrollToBottom: function(force) {
    if (force || this.shouldScrollToBottom()) {
      this.element.scrollTop = this.element.scrollHeight;
    }
  },

  getNicknames: function() {
    return this.nicks;
  },

  updateNicks: function(nicks) {
    this.nicks = nicks;
    if (this.active) this.application.displayNicks(this.nicks);
  }
});
