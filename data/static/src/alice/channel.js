Alice.Channel = Class.create({
  initialize: function (name, id, active, session) {
    this.name = name;
    this.id = id;
    this.session = session;
    this.active = active;
    
    this.elem = $(id);
    this.tab = $(id + "_tab");
    this.input = $(id + "_msg");
    this.tabButton = $(id + "_tab_button");
    this.form = $(id + "_form");
    this.topic = $(id + "_topic");
    this.messages = $(id + "_messages");
    this.lastnick = "";
    
    this.msgHistory = [""];
    this.currentMsg = 0;
    
    var self = this;
    
    this.form.observe("submit", this.sayMessage.bind(this));
    this.tab.observe("mousedown", this.focus.bind(this));
    this.tabButton.observe("click", function (e) {self.close(); Event.stop(e);});
    this.tabButton.observe("mousedown", function (e) {Event.stop(e)});
    /*
    this.autocompleter = new Alice.Autocompleter(
      this.input, this.id + "_autocomplete_choices",
      "/autocomplete",
      {
        parameters: Object.toQueryString({chan: self.name, session: self.session}),
        method: 'get',
        updateElement: function (elem) {
          if (! elem.innerHTML.match(/^\//)) {
            elem.innerHTML = elem.innerHTML + ":";
          }
          self.input.value = self.input.value.replace(/\S+\b$/, elem.innerHTML + " ");
        }
      }
    );
    */
  },
  
  nextMessage: function () {
    if (this.msgHistory.length <= 1) return;
    this.currentMsg++;
    if (this.currentMsg >= this.msgHistory.length)
      this.currentMsg = 0;
    this.input.value = this.msgHistory[this.currentMsg];
  },
  
  previousMessage: function () {
    if (this.msgHistory.length <= 1) return;
    this.currentMsg--;
    if (this.currentMsg < 0)
      this.currentMsg = this.msgHistory.length - 1;
    this.input.value = this.msgHistory[this.currentMsg];
  },
  
  sayMessage: function (event) {
    alice.connection.sendMessage(this.form);
    this.currentMsg = 0;
    this.msgHistory.push(this.input.value);
    this.input.value = '';
    Event.stop(event);
  },
  
  unFocus: function () {
    this.active = false;
    alice.previousFocus = this;
    this.elem.removeClassName('active');
    this.tab.removeClassName('active');
    if (this.tab.previous()) this.tab.previous().removeClassName("leftof_active");
  },
  
  focus: function (event) {
    document.title = this.name;
    if (alice.activeChannel()) alice.activeChannel().unFocus();
    this.active = true;
    this.tab.addClassName('active');
    this.elem.addClassName('active');
    this.tab.removeClassName("unread");
    this.tab.removeClassName("highlight");
    this.tab.removeClassName("leftof_active");
    if (this.tab.previous()) this.tab.previous().addClassName("leftof_active");
    this.scrollToBottom(true);
    this.input.focus();
  },
  
  close: function (event) {
    alice.removeChannel(this);
    this.tab.remove();
    this.elem.remove();
  },
  
  displayTopic: function(topic) {
    this.topic.innerHTML = alice.linkFilter(topic);
  },
  
  addMessage: function(message) {
    if (message.html || message.full_html) {
      var last_message = $$('#' + message.chanid + ' .'
        + message.nick + ':last-child .msg').first();
      if ((message.nick == "Shaniqua" || message.nick == "root" || message.nick == "p6eval")
        && last_message) {
        var html = alice.applyFilters(message.html);
        last_message.insert("<br />" + html);
      }
      else if (message.event == "say" && last_message) {
        var html = stripNick(alice.applyFilters(message.full_html));
        this.messages.insert(html);
      }
      else if (message.event == "topic") {
        this.messages.insert(alice.linkFilter(message.full_html));
        this.displayTopic(message.message);
      }
      else {
        var html = alice.applyFilters(message.full_html);
        this.messages.insert(html);
      }
      
      if (! alice.isFocused && message.highlight)
        growlNotify(message);

      // scroll to bottom or highlight the tab
      if (this.elem.hasClassName('active'))
        this.scrollToBottom();
      else if (message.event == "say" && message.highlight)
        this.tab.addClassName("highlight");
      else if (message.event == "say")
        this.tab.addClassName("unread");
    }
    else if (message.event == "announce") {
      this.messages.insert("<li class='message'><div class='msg announce'>"
        +message.str+"</div></li>");
      this.scrollToBottom();
    }

    var messages = $$('#' + message.chanid + ' li');
    if (messages.length > 250) messages.first().remove();
  },
  
  scrollToBottom: function (force) {
    if (! force) {
      var lastmsg = $$('#' + this.id + ' li:last-child').first();
      if (! lastmsg) return;
      var msgheight = lastmsg.offsetHeight; 
      var bottom = this.elem.scrollTop + this.elem.offsetHeight;
      var height = this.elem.scrollHeight;
    }
    if (force || bottom + msgheight >= height)
      this.elem.scrollTop = this.elem.scrollHeight;
  }
});
