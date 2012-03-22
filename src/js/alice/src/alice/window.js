Alice.Window = Class.create({
  initialize: function(application, serialized) {
    this.application = application;
    
    this.element = $(serialized['id']);
    this.title = serialized['title'];
    this.type = serialized['type'];
    this.hashtag = serialized['hashtag'];
    this.network = serialized['network'];
    this.id = this.element.identify();
    this.active = false;
    this.topic = serialized['topic'];
    this.tab = $(this.id + "_tab");
    this.tab_layout = this.tab.getLayout();
    this.tabButton = $(this.id + "_tab_button");
    this.messages = this.element.down('.messages');
    this.visibleNick = "";
    this.visibleNickTimeout = "";
    this.lasttimestamp = null;
    this.nicks = [];
    this.nicks_order = [];
    this.statuses = [];
    this.messageLimit = this.application.messageLimit;
    this.chunkSize = this.messageLimit / 2;
    this.msgid = -1;
    this.visible = true;
    this.forceScroll = false;
    this.lastScrollPosition = 0;
    
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
        if (this.type != "channel" || confirm("Are you sure you want to leave "+this.title+"?"))
          this.close()
    }.bind(this));

    this.messages.observe("mouseover", this.showNick.bind(this));
  },

  checkScrollBack: function() {
    if (this.active && this.element.scrollTop <= 150) {
      clearInterval(this.scrollListener);
      var first = this.messages.down("li[id]");
      if (first) {
        first = first.id.replace("msg-", "") - 1;
        this.messageLimit += this.chunkSize;
      }
      else {
        first = this.msgid;
      }
      this.application.log("requesting chunk" + first);
      this.tab.addClassName("loading");
      this.application.getBacklog(this, first, this.chunkSize);
    }
    else {
      clearTimeout(this.scrollListener);
      this.scrollListener = setTimeout(this.checkScrollBack.bind(this), 1000);
    }
  },

  clearMessages: function() {
    clearTimeout(this.scrollListener);
    this.messages.update("");
    this.lastNick = "";
  },

  updateTabLayout: function() {
    this.tab_layout = this.tab.getLayout();
  },

  getTabPosition: function() {
    var shift = this.application.tabShift();

    var tabs_width = this.application.tabsWidth();
    var tab_width = this.tab_layout.get("width");

    var offset_left = this.tab_layout.get("left") + shift;
    var offset_right = tabs_width - (offset_left + tab_width);

    var overflow_right = Math.abs(Math.min(0, offset_right));
    var overflow_left = Math.abs(Math.min(0, offset_left));

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
    this.lastScrollPosition = this.captureScrollPosition();
    this.active = false;
    this.element.removeClassName('active');
    this.tab.removeClassName('active');
    clearTimeout(this.scrollListener);
    clearTimeout(this.focusTimer);
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

    this.application.previousFocus = this.application.activeWindow();
    if (this != this.application.previousFocus)
      this.application.previousFocus.unFocus();

    // focusing an already focused window can make the
    // scroll position jump to its position from its last
    // unfocus. doh.
    if (!this.active) {
      this.active = true;

      this.scrollToPosition(this.lastScrollPosition);

      this.focusTimer = setTimeout(function(){
        this.scrollToPosition(this.lastScrollPosition);
        if (!this.scrollBackEmpty) this.checkScrollBack();
      }.bind(this), 400);
    }

    this.element.addClassName('active');
    this.tab.addClassName('active');

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
    var new_hash = "#" + this.application.selectedSet + this.hashtag;
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
    var classes = ["unread"];
    if (classname) classes.push(classname);

    classes.each(function(c){this.tab.addClassName(c)}.bind(this));
    this.application.highlightChannelSelect(this.id, classes);
    this.statuses = classes;
  },
  
  disable: function () {
    this.markRead();
    this.tab.addClassName('disabled');
  },
  
  enable: function () {
    this.tab.removeClassName('disabled');
  },
  
  close: function(event) {
    this.tab.remove();
    this.element.remove();
    this.application.removeWindow(this);
  },
  
  showHappyAlert: function (message) {
    this.messages.insert(
      "<li class='event happynotice'><div class='msg'>"+message+"</div></li>"
    );
    this.scrollToPosition(0);
  },
  
  showAlert: function (message) {
    this.messages.insert(
      "<li class='event notice'><div class='msg'>"+message+"</div></li>"
    );
    this.scrollToPosition(0);
  },

  announce: function (message) {
    message = message.escapeHTML();
    this.messages.insert(
      "<li class='message monospaced announce'><div class='msg'>"+message+"</div></li>"
    );
    this.scrollToPosition(0);
  },

  trimMessages: function() {
    this.messages.select("li").reverse().slice(this.messageLimit).invoke("remove");
  },

  addChunk: function(chunk) {
    if (chunk.nicks) this.updateNicks(chunk.nicks);
    clearTimeout(this.scrollListener);

    if (chunk.range.length == 0) {
      this.scrollBackEmpty = true;
      this.tab.removeClassName("loading");
      return;
    }

    var position = this.captureScrollPosition();

    if (parseInt(chunk['range'][0]) > this.msgid) {
      this.messages.insert({"bottom": chunk['html']});
      this.trimMessages();
      this.msgid = parseInt(chunk['range'][1]);
    }
    else {
      this.bulk_insert = true;
      this.messages.insert({"top": chunk['html']});
    }

    var original_timestamp = this.lasttimestamp;
    this.lasttimestamp = null;

    this.messages.select("li:not(.filtered)").each(function (li) {
      this.application.applyFilters(li, this);
    }.bind(this));

    this.lasttimestamp = original_timestamp;
    this.bulk_insert = false;

    this.scrollToPosition(position);
    setTimeout(function(){this.removeClassName("loading")}.bind(this.tab), 1000);
    this.scrollListener = setTimeout(this.checkScrollBack.bind(this), 1000);
  },

  addMessage: function(message) {
    if (!message.html || message.msgid <= this.msgid) return;
    
    if (message.msgid) this.msgid = message.msgid;
    if (message.nicks) this.updateNicks(message.nicks);

    var position = this.captureScrollPosition();
    
    this.messages.insert(message.html);
    this.trimMessages();

    this.scrollToPosition(position);

    var li = this.messages.select("li").last();
    this.application.applyFilters(li, this);

    this.scrollToPosition(position);

    if (message.event == "topic") {
      this.topic = message.body;
      if (this.active) this.application.displayTopic(this.topic);
    }

    this.element.redraw();
    this.promoteNick(message.nick);
  },

  promoteNick: function(nick) {
    // just return if this nick is already at the end
    if (this.nicks_order.last() == nick) return; 

    // remove nick from list if it exists
    var index = this.nicks_order.indexOf(nick);
    if (index > -1) this.nicks_order.splice(index, 1);

    this.nicks_order.push(nick);
  },

  captureScrollPosition: function() {
    if (!this.active) return;
    if (this.forceScroll) return 0;

    var bottom = this.element.scrollTop + this.element.offsetHeight;
    var height = this.element.scrollHeight;

    return height - bottom;
  },
  
  scrollToPosition: function(position) {
    if (!this.active) return;
    this.element.scrollTop = this.element.scrollHeight - this.element.offsetHeight - position;
  },

  getNicknames: function () {
    return this.nicks.sort(function(a, b) {

      var pos_a = this.nicks_order.indexOf(a),
          pos_b = this.nicks_order.indexOf(b);

      if (pos_a == pos_b)
        return a.toLowerCase().localeCompare(b.toLowerCase());
      else if (pos_a > pos_b)
        return -1;
      else if (pos_a < pos_b)
        return 1;

    }.bind(this));
  },

  updateNicks: function(nicks) {
    this.nicks = nicks;
    if (this.active) this.application.displayNicks(this.nicks);
  },

  removeImage: function(e) {
    e.stop();
    var div = e.findElement('div.image');
    if (div) {
      var a = div.down("a");
      var id = a.identify();
      a.update(a.href);
      a.style.display = "inline";
      div.replace(a);
      a.observe("click", function(e){e.stop();this.inlineImage(a)}.bind(this));
    }
  },

  inlineImage: function(a) {
    a.stopObserving("click");
    var src = a.readAttribute("img") || a.innerHTML;
    var prefix = alice.options.image_prefix;

    var img = new Element("IMG", {src: prefix + src});
    img.hide();

    img.observe("load", function(){
      var wrap = new Element("DIV", {"class": "image"});
      var hide = new Element("A", {"class": "hideimg"});
      var position = this.captureScrollPosition();

      img.show();
      a.replace(wrap);
      wrap.insert(a);
      a.update(img);
      a.insert(hide);
      a.style.display = "inline-block";
      hide.observe("click", this.removeImage.bind(this));
      hide.update("hide");

      this.scrollToPosition(position);
    }.bind(this));

    a.insert({after: img});
  }
});
