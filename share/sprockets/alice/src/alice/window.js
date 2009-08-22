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
    this.nicks = [];
    
    this.submit.observe("click", function (e) {this.input.send(); e.stop()}.bind(this));
    this.tab.observe("mousedown", this.focus.bind(this));
    this.tabButton.observe("click", function(e) { this.close() && e.stop() }.bind(this));
    this.tabButton.observe("mousedown", function(e) { e.stop() });
  },
  
  unFocus: function() {
    this.active = false;
    this.application.previousFocus = this;
    this.element.removeClassName('active');
    this.tab.removeClassName('active');
    if (this.tab.previous()) this.tab.previous().removeClassName("leftof_active");
  },
  
  focus: function(event) {
    document.title = this.title;
    if (this.application.activeWindow()) this.application.activeWindow().unFocus();
    this.active = true;
    this.tab.addClassName('active');
    this.element.addClassName('active');
    this.tab.removeClassName("unread");
    this.tab.removeClassName("highlight");
    this.tab.removeClassName("leftof_active");
    if (this.tab.previous()) this.tab.previous().addClassName("leftof_active");
    this.scrollToBottom(true);
    if (!Prototype.Browser.MobileSafari) this.input.focus();
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
      if (message.nick && message.nick == this.lastNick) {
        if (this.application.messagesAreMonospacedFor(message.nick))
          this.messages.down('li:last-child div.msg').insert(
            "<br>" + this.application.applyFilters(message.html));
        else if (message.event == "say")
          this.messages.insert(
            Alice.stripNick(this.application.applyFilters(message.full_html)));
      }
      else {
        if (message.event == "topic") {
          this.messages.insert(Alice.makeLinksClickable(message.full_html));
          this.displayTopic(message.body);
        }
        else {
          this.messages.insert(this.application.applyFilters(message.full_html));
        }
      }

      this.lastNick = "";
      if (message.event == "say" && message.nick)
        this.lastNick = message.nick;
      
      this.messages.redraw();
      
      if (!this.application.isFocused && message.highlight)
        Alice.growlNotify(message);
      
      if (message.nicks && message.nicks.length)
        this.nicks = message.nicks;

      // scroll to bottom or highlight the tab
      if (this.element.hasClassName('active'))
        this.scrollToBottom();
      else if (message.event == "say" && message.highlight)
        this.tab.addClassName("highlight");
      else if (message.event == "say")
        this.tab.addClassName("unread");
    }

    var messages = this.messages.childElements();
    if (messages.length > 250) messages.first().remove();
  },
  
  scrollToBottom: function(force) {
    if (!force) {
      var lastmsg = this.messages.down('li:last-child');
      if (!lastmsg) return;
      var msgheight = lastmsg.offsetHeight; 
      var bottom = this.messages.scrollTop + this.messages.offsetHeight;
      var height = this.messages.scrollHeight;
    }
    if (force || bottom + msgheight + 100 >= height)
      this.messages.scrollTop = this.messages.scrollHeight;
  },
  
  getNicknames: function() {
     return this.nicks;
  }
});
