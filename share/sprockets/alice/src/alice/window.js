Alice.Window = Class.create({
  initialize: function(application, element, title, active) {
    this.application = application;
    
    this.element = $(element);
    this.title = title;
    this.id = this.element.identify();
    this.active = active;
    
    this.tab = $(this.id + "_tab");
    this.input = new Alice.Input(this, this.id + "_msg");
    this.tabButton = $(this.id + "_tab_button");
    this.form = $(this.id + "_form");
    this.topic = $(this.id + "_topic");
    this.messages = $(this.id + "_messages");
    this.submit = $(this.id + "_submit");
    this.lastNick = "";
    this.nicksVisible = false;
    this.visibleNick = "";
    this.visibleNickTimeout = "";
    this.nicks = [];
    
    this.submit.observe("click", function (e) {this.input.send(); e.stop()}.bind(this));
    this.tab.observe("mousedown", function(e) {
      if (!this.active) {this.focus(); this.active = false}}.bind(this));
    this.tab.observe("click", function(e) {this.active = true}.bind(this));
    this.tabButton.observe("click", function(e) {if (this.active) this.close()}.bind(this));
    document.observe("mouseover", this.showNick.bind(this));
  },
  
  unFocus: function() {
    this.active = false;
    this.application.previousFocus = this;
    this.element.removeClassName('active');
    this.tab.removeClassName('active');
    if (this.tab.previous()) this.tab.previous().removeClassName("leftof_active");
  },

  showNick: function (e) {
    var li = e.findElement("#" + this.id + " ul.messages li.message");
    if (li) {
      if (this.nicksVisible || li == this.visibleNick) return;
      clearTimeout(this.visibleNickTimeout);

      this.visibleNick = li;
      var span = li.down().down(2);

      if (span) {
        this.visibleNickTimeout = setTimeout(function(span) {
          span.style.webkitTransition = "opacity 0.1s ease-in-out";
          span.style.opacity = 1;
          setTimeout(function(){
            if (this.nicksVisible) return;
            span.style.webkitTransition = "opacity 0.25s ease-in";
            span.style.opacity = 0
          }.bind(this,span) , 1000);
        }.bind(this,span), 500);
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
    }
    else {
      this.messages.select("span.nickhint").each(function(span){
        span.style.webkitTransition = "opacity 0.1s ease-in-out";
        span.style.opacity = 1;
      })
    }
    this.nicksVisible = !this.nicksVisible;
  },

  focus: function(event) {
    document.title = this.title;
    if (this.application.activeWindow()) this.application.activeWindow().unFocus();
    this.active = true;
    this.tab.addClassName('active');
    this.element.addClassName('active');
    this.markRead();
    this.tab.removeClassName("leftof_active");
    if (this.tab.previous()) this.tab.previous().addClassName("leftof_active");
    this.scrollToBottom(true);
    if (!Prototype.Browser.MobileSafari) this.input.focus();
    this.element.redraw();
  },
  
  markRead: function () {
    this.tab.removeClassName("unread");
    this.tab.removeClassName("highlight");
  },
  
  close: function(event) {
    this.application.removeWindow(this);
    this.tab.remove();
    this.element.remove();
  },
  
  displayTopic: function(topic) {
    this.topic.update(Alice.makeLinksClickable(topic));
  },
  
  addMessage: function(message) {
    if (message.html || message.full_html) {
      if (message.event == "say" && message.nick && message.nick == this.lastNick) {
        if (this.application.messagesAreMonospacedFor(message.nick) || message.monospaced)
          this.messages.down('li:last-child div.msg').insert(
            "<br>" + this.application.applyFilters(message.html));
        else if (message.event == "say")
          this.messages.down('li:last-child div.msg').insert(
            Alice.stripNick(this.application.applyFilters("<hr class=\"consecutive\">"+message.html)));
      }
      else {
        if (message.event == "topic") {
          this.messages.insert(Alice.makeLinksClickable(message.full_html));
          this.displayTopic(message.body.escapeHTML());
        }
        else {
          this.messages.insert(message.full_html);
          var node = this.messages.down("li:last-child div.msg");
          node.innerHTML = this.application.applyFilters(node.innerHTML);
          var span = this.messages.down('li:last-child span.nickhint');
          if (span && this.nicksVisible) {
            span.style.webkitTransition = 'none 0 linear';
            span.style.opacity = 1;
          }
        }
      }

      this.lastNick = "";
      if (message.event == "say" && message.nick)
        this.lastNick = message.nick;
      
      if (!this.application.isFocused && message.highlight)
        Alice.growlNotify(message);
      
      if (message.nicks && message.nicks.length)
        this.nicks = message.nicks;

      // scroll to bottom or highlight the tab
      if (this.element.hasClassName('active'))
        this.scrollToBottom();
      else if (!message.buffered && this.title != "info") {
        if (message.event == "say" && message.highlight)
          this.tab.addClassName("highlight");
        else if (message.event == "say")
          this.tab.addClassName("unread");
      }
    }

    var messages = this.messages.childElements();
    if (messages.length > 250) messages.first().remove();
    
    this.element.redraw();
  },
  
  scrollToBottom: function(force) {
    if (!force) {
      var lastmsg = this.messages.down('li:last-child');
      if (!lastmsg) return;
      var msgheight = lastmsg.offsetHeight; 
      var bottom = this.messages.scrollTop + this.messages.offsetHeight;
      var height = this.messages.scrollHeight;
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
