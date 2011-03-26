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
    this.tab_layout = this.tab.getLayout();
    this.tabButton = $(this.id + "_tab_button");
    this.messages = this.element.down('.messages');
    this.visibleNick = "";
    this.visibleNickTimeout = "";
    this.lasttimestamp = new Date(0);
    this.nicks = [];
    this.statuses = [];
    this.messageLimit = this.application.isMobile ? 50 : 200;
    this.msgid = 0;
    this.visible = true;
    
    this.setupEvents();
  },

  hide: function() {
    this.element.hide();
    this.tab.addClassName('hidden');
    this.tab.removeClassName('visible');
    this.visible = false;
  },

  show: function() {
    this.element.show();
    this.tab.addClassName('visible');
    this.tab.removeClassName('hidden');
    this.visible = true;
    this.updateTabLayout();
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

  updateTabLayout: function() {
    this.tab_layout = this.tab.getLayout();
  },

  getTabPosition: function() {
    var shift = this.application.tabShift();

    var doc_width = this.application.width - 24;
    var tab_width = this.tab_layout.get("width");

    var offset_left = this.tab_layout.get("left") + shift;
    var offset_right = doc_width - (offset_left + tab_width);

    var overflow_right = Math.abs(Math.min(0, offset_right));
    var overflow_left = Math.abs(Math.min(0, offset_left));

    if (this.tab.previous('.visible')) {
      if (overflow_left) {
        overflow_left += 24;
      }
      else if (offset_left < 24 && offset_left > 0) {
        overflow_left += 24 - offset_left;
      }
    }

    if (!overflow_left && this.tab.next('.visible')) {
      if (overflow_right) {
        overflow_right += 24;
      }
      else if (offset_right < 24 && offset_right > 0) {
        overflow_right += 24 - offset_right;
      }
    }

    return {
      right: overflow_right,
      left: overflow_left
    };
  },

  shiftTab: function() {
    var left = null
      , time = 0
      , pos = this.getTabPosition(); 

    if (pos.left) {
      this.application.shiftTabs(pos.left);
    }
    else if (pos.right) {
      this.application.shiftTabs(-pos.right);
    }
  },

  unFocus: function() {
    this.active = false;
    this.element.removeClassName('active');
    this.tab.removeClassName('active');
    this.addFold();
  },

  addFold: function() {
    this.messages.select("li.fold").invoke("removeClassName", "fold");
    var last = this.messages.childElements().last();
    if (last) last.addClassName("fold");
  },

  showNick: function (e) {
    var li = e.findElement("li.message");
    if (li && li.hasClassName("avatar")) {
      if (this.application.overlayVisible || li == this.visibleNick) return;
      clearTimeout(this.visibleNickTimeout);

      this.visibleNick = li;
      var nick;
      if (li.hasClassName("consecutive")) {
        var stem = li.previous("li:not(.consecutive)");
        if (!stem) return;
        nick = stem.down("span.nick");
      } else {
        nick = li.down("span.nick");
      }

      if (nick) {
        this.visibleNickTimeout = setTimeout(function(nick) {
          if (nick) nick.style.opacity = 1;

          setTimeout(function(){
            if (this.application.overlayVisible) return;
            if (nick) nick.style.opacity = 0;
          }.bind(this, nick) , 1000);
        }.bind(this, nick), 500);
      }
    }
    else {
      this.visibleNick = "";
      clearTimeout(this.visibleNickTimeout);
    }
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

    this.shiftTab();

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
    this.statuses = [];
    this.application.unHighlightChannelSelect(this.id);
  },

  markUnread: function(classname) {
    this.tab.addClassName(classname);
    this.statuses.push(classname);
    this.statuses = this.statuses.uniq();
    this.application.highlightChannelSelect(this.id, classname);
  },

  status_class: function() {
    return this.statuses.join(" ");
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
    if (chunk.nicks) this.updateNicks(chunk.nicks);

    var scroll = this.shouldScrollToBottom();

    this.messages.insert({bottom: chunk.html});
    this.trimMessages();
    if (scroll) this.scrollToBottom(true);

    // so the tab doesn't get highlighted :|
    this.bulk_insert = true;

    var messages = this.messages.select("li");
    messages.each(function (li) {
      this.application.applyFilters(li, this);
    }.bind(this));

    this.bulk_insert = false;

    if (scroll) this.scrollToBottom(true);

    var last = messages.last();
    if (last && last.id) this.msgid = last.id.replace("msg-", "");
  },

  addMessage: function(message) {
    if (!message.html || message.msgid <= this.msgid) return;
    
    if (message.msgid) this.msgid = message.msgid;
    if (message.nicks) this.updateNicks(message.nicks);

    var scroll = this.shouldScrollToBottom();
    
    this.messages.insert(message.html);
    this.trimMessages();
    if (scroll) this.scrollToBottom(true);

    var li = this.messages.select("li").last();
    this.application.applyFilters(li, this);

    if (scroll) this.scrollToBottom(true);

    if (message.event == "topic") {
      this.topic = message.body;
      if (this.active) this.application.displayTopic(this.topic);
    }

    this.element.redraw();
  },

  shouldScrollToBottom: function() {
    if (!this.active) return false;

    var bottom = this.element.scrollTop + this.element.offsetHeight;
    var height = this.element.scrollHeight;

    return bottom + 100 >= height;
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
  },

  removeImage: function(e) {
    var div = e.findElement('div.image');
    if (div) {
      var img = div.down('a img');
      var a = img.up('a');
      if (img) img.replace(a.href);
      e.element().remove();
      a.observe("click", function(e){e.stop();this.inlineImage(a)}.bind(this));
    }
  },

  inlineImage: function(a) {
    if(a.innerHTML.indexOf('nsfw') !== -1) return;
    a.stopObserving("click");

    var scroll = this.shouldScrollToBottom();

    var img = new Element("IMG", {src: alice.options.image_prefix + a.innerHTML});
    img.observe("load", function(){
      img.up("div.image").style.display = "inline-block";
      if (scroll) this.scrollToBottom(true);
    }.bind(this));

    var wrap = new Element("DIV");
    var div = new Element("DIV", {"class": "image"});
    var hide = new Element("A", {"class": "hideimg"});

    hide.observe("click", this.removeImage.bind(this));
    hide.update("hide");
    wrap.insert(div);

    a = a.replace(wrap);
    div.insert(a);
    div.insert(hide);
    a.update(img);
  }
});
