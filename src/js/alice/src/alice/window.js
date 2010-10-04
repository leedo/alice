Alice.Window = Class.create({
  initialize: function(application, element, title, active, hashtag) {
    this.application = application;
    
    this.element = $(element);
    this.title = title;
    this.hashtag = hashtag;
    this.id = this.element.identify();
    this.active = active;
    this.tab = $(this.id + "_tab");
    this.input = new Alice.Input(this, this.id + "_msg");
    this.tabButton = $(this.id + "_tab_button");
    this.tabOverflowButton = $(this.id + "_tab_overflow_button");
    this.form = $(this.id + "_form");
    this.topic = $(this.id + "_topic");
    this.messages = this.element.down('.message_wrap');
    this.submit = $(this.id + "_submit");
    this.nicksVisible = false;
    this.visibleNick = "";
    this.visibleNickTimeout = "";
    this.nicks = [];
    this.messageLimit = this.application.isMobile ? 50 : 250;
    this.msgid = 0;
    
    this.setupEvents();
    this.setupTopic();
  },

  setupTopic: function() {
    // setup topic expanding on click (if it is multiline)
    if (this.topic) {
      var orig_height = this.topic.getStyle("height");
      this.topic.observe("click", function(e) {
        if (this.topic.getStyle("height") == orig_height) {
          this.topic.setStyle({height: "auto"});
        } else {
          this.topic.setStyle({height: orig_height});
        }
      }.bind(this));
      this.makeTopicClickable();
    }
  },

  setupEvents: function() {
    this.submit.observe("click", function (e) {this.input.send(); e.stop()}.bind(this));

    // huge mess of click logic to get the right behavior.
    // (e.g. clicking on unfocused (x) button does not close tab)
    this.tab.observe("mousedown", function(e) {
      if (!this.active) {this.focus(); this.focusing = true}
    }.bind(this));

    this.tab.observe("click", function(e) {this.focusing = false}.bind(this));

    this.tabButton.observe("click", function(e) {
      if (this.active && !this.focusing) this.close()}.bind(this));

    this.messages.observe("mouseover", this.showNick.bind(this));
  },

  setupMessages: function() {
    // fix height of non-consecutive avatar messages
    this.messages.select('li.avatar:not(.consecutive) + li.consecutive').each(function (li) {
      li.previous().down('div.msg').setStyle({minHeight:'0px'});
    });

    this.messages.select('li.monospace + li.monospace.consecutive').each(function(li) {
      li.previous().down('div.msg').setStyle({paddingBottom:'0px'});
    });

    // change timestamps from epoch to local time
    this.messages.select('span.timestamp').each(function(elem) {
      if (elem.innerHTML) {
        elem.innerHTML = Alice.epochToLocal(elem.innerHTML.strip(), alice.options.timeformat);
        elem.style.opacity = 1;
      }
    });

    if (this.application.isJankyScroll) {
      this.resizeMessagearea();
      this.scrollToBottom();
    }

    if (this.active) this.scrollToBottom(true);

    // wait a second to load images, otherwise the browser will say "loading..."
    setTimeout(function () {
      this.messages.select('li.message div.msg').each(function (msg) {
        msg.innerHTML = this.application.applyFilters(msg.innerHTML);
      }.bind(this));
    }.bind(this), this.application.loadDelay);

    var last = this.messages.down("li:last-child");
    if (last && last.id) {
      this.msgid = last.id;
    }
  },
  
  isTabWrapped: function() {
    return this.tab.offsetTop > 0;
  },
  
  unFocus: function() {
    this.active = false;
    this.input.uncancelNextFocus();
    this.element.removeClassName('active');
    this.tab.removeClassName('active');
    this.tabOverflowButton.selected = false;
  },

  showNick: function (e) {
    var li = e.findElement("#" + this.id + " ul.messages li.message");
    if (li) {
      if (this.nicksVisible || li == this.visibleNick) return;
      clearTimeout(this.visibleNickTimeout);

      this.visibleNick = li;
      var nick; var time;
      if (li.hasClassName("consecutive")) {
        var stem = li.previous("li:not(.consecutive)");
        if (!stem) return;
        nick = stem.down(".nickhint");
        time = stem.down(".timehint");
      } else {
        nick = li.down(".nickhint");
        time = li.down(".timehint");
      }

      if (nick || time) {
        this.visibleNickTimeout = setTimeout(function(nick, time) {
          if (nick) {
            nick.style.opacity = 1;
            nick.style.webkitTransition = "opacity 0.1s ease-in-out";
          }
          if (time) {
            time.style.webkitTransition = "opacity 0.1s ease-in-out"; 
            time.style.opacity = 1;
          }
          setTimeout(function(){
            if (this.nicksVisible) return;
            if (nick) {
              nick.style.webkitTransition = "opacity 0.25s ease-in";
              nick.style.opacity = 0;
            }
            if (time) {
              time.style.webkitTransition = "opacity 0.25s ease-in";
              time.style.opacity = 0;
            }
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
      this.messages.select("span.nickhint").each(function(span){
        span.style.webkitTransition = "opacity 0.1s ease-in";
        span.style.opacity = 0;
      });
      this.messages.select("div.timehint").each(function(span){
        span.style.webkitTransition = "opacity 0.1s ease-in";
        span.style.opacity = 0;
      });
    }
    else {
      this.messages.select("span.nickhint").each(function(span){
        span.style.webkitTransition = "opacity 0.1s ease-in-out";
        span.style.opacity = 1;
      });
      this.messages.select("div.timehint").each(function(span){
        span.style.webkitTransition = "opacity 0.1s ease-in-out";
        span.style.opacity = 1;
      });
    }
    this.nicksVisible = !this.nicksVisible;
  },

  focus: function(event) {
    document.title = this.title;
    this.application.previousFocus = this.application.activeWindow();
    this.application.windows().invoke("unFocus");
    this.active = true;
    this.tab.addClassName('active');
    this.element.addClassName('active');
    this.tabOverflowButton.selected = true;
    this.markRead();
    this.scrollToBottom(true);

    if (!this.application.isMobile) this.input.focus();

    if (this.application.isJankyScroll) {
      this.resizeMessagearea();
      this.scrollToBottom();
    }

    this.element.redraw();
    this.setWindowHash();
    this.application.updateChannelSelect();
  },

  setWindowHash: function () {
    window.location.hash = this.hashtag;
    window.location = window.location.toString();
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
  
  displayTopic: function(topic) {
    this.topic.update(topic);
    this.makeTopicClickable();
  },

  makeTopicClickable: function() {
    if (!this.topic) return;
    this.topic.innerHTML = this.topic.innerHTML.replace(/(https?:\/\/[^\s]+)/ig, '<a href="$1" target="_blank" rel="noreferrer">$1</a>');
  },
  
  resizeMessagearea: function() {
    var top = this.messages.up().cumulativeOffset().top;
    var bottom = this.input.element.getHeight() + 14;
    this.messages.setStyle({
      position: 'absolute',
      top: top+"px",
      bottom: bottom + "px",
      right: "0px",
      left: "0px",
      height: 'auto'
    });
  },
  
  showHappyAlert: function (message) {
    this.messages.down('ul').insert(
      "<li class='event happynotice'><div class='msg'>"+message+"</div></li>"
    );
    this.scrollToBottom();
  },
  
  showAlert: function (message) {
    this.messages.down('ul').insert(
      "<li class='event notice'><div class='msg'>"+message+"</div></li>"
    );
    this.scrollToBottom();
  },

  trimMessages: function() {
    this.messages.select("li").reverse().slice(this.messageLimit).invoke("remove");
  },
  
  addMessage: function(message) {
    if (!message.html) return;
    
    this.messages.down('ul').insert(message.html);
    if (message.msgid) this.msgid = message.msgid;
    this.trimMessages();

    //this.messages.down('ul').insert(Alice.uncacheGravatar(message.html));
    var li = this.messages.down('ul.messages > li:last-child');
    
    if (message.consecutive) {
      var prev = li.previous(); 
      if (prev && prev.hasClassName("avatar") && !prev.hasClassName("consecutive")) {
        prev.down('div.msg').setStyle({minHeight: '0px'});
      }
      if (prev && prev.hasClassName("monospace")) {
        prev.down('div.msg').setStyle({paddingBottom: '0px'});
      }
    }
    
    if (message.event == "say") {
      var msg = li.down('div.msg');
      msg.innerHTML = this.application.applyFilters(msg.innerHTML);
      
      var nick = li.down('span.nickhint');
      if (nick && this.nicksVisible) {
        nick.style.webkitTransition = 'none 0 linear';
        nick.style.opacity = 1;
      }
      var time = li.down('div.timehint');
      if (time && this.nicksVisible) {
        time.style.webkitTransition = 'none 0 linear';
        time.style.opacity = 1;
      }
      
      if (message.consecutive) {
        var avatar = li.previous(".avatar:not(.consecutive)");
        if (avatar && avatar.down(".timehint"))
          avatar.down(".timehint").innerHTML = message.timestamp;
      }
    }
    else if (message.event == "topic") {
      this.displayTopic(message.body.escapeHTML());
    }
    
    if (!this.application.isFocused && message.highlight && message.window.title != "info") {
      message.body = li.down(".msg").innerHTML.stripTags();
      Alice.growlNotify(message);
      this.application.addMissed();
    }
    
    if (message.nicks && message.nicks.length)
      this.nicks = message.nicks;
    
    // scroll to bottom or highlight the tab
    if (this.element.hasClassName('active'))
      this.scrollToBottom();
    else if (this.title != "info") {
      if (message.event == "say") {
        this.tab.addClassName("unread");
        this.tabOverflowButton.addClassName("unread");
        if (this.isTabWrapped()) this.application.highlightChannelSelect();
      }
      if (message.highlight) {
        this.tab.addClassName("highlight");
      }
    }

    // fix timestamps
    li.select("span.timestamp").each(function(elem) {
      elem.innerHTML = Alice.epochToLocal(elem.innerHTML.strip(), this.application.options.timeformat);
      elem.style.opacity = 1;
    }.bind(this));

    this.element.redraw();
  },
  
  scrollToBottom: function(force) {
    var bottom, height;

    if (!force) {
      var lastmsg = this.messages.down('ul.messages > li:last-child');
      if (!lastmsg) return;
      var msgheight = lastmsg.offsetHeight; 
      bottom = this.messages.scrollTop + this.messages.offsetHeight;
      height = this.messages.scrollHeight;
    }

    if (force || bottom + msgheight + 100 >= height) {
      this.messages.scrollTop = this.messages.scrollHeight;
      this.element.redraw();
    }
  },

  getNicknames: function() {
    return this.nicks;
  }
});
