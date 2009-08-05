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
    
    var self = this;
    
    this.form.observe("submit", alice.connection.sayMessage);
    this.tab.observe("click", this.focus.bind(this));
    this.tabButton.observe("click", this.close.bind(this));
    
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
  },
  
  unFocus: function () {
    this.active = false;
    alice.previousFocus = alice.channelLookup[this.id];
    this.elem.removeClassName('active');
    this.tab.removeClassName('active');
    if (this.tab.previous()) this.tab.previous().removeClassName("leftof_active");
  },
  
  focus: function () {
    document.title = this.name;
    alice.activeChannel().unFocus();
    this.active = true;
    this.tab.addClassName('active');
    this.elem.addClassName('active');
    this.tab.removeClassName("unread");
    this.tab.removeClassName("highlight");
    if (this.tab.previous()) this.tab.previous().addClassName("leftof_active");
    this.scrollToBottom(true);
    this.input.focus();
  },
  
  close: function (event) {
    alice.removeChannel(this);
    this.tab.remove();
    this.elem.remove();
    Event.stop(event);
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
      else {
        var html = alice.applyFilters(message.full_html);
        this.messages.insert(html);
      }

      if (message.event == "topic") this.displayTopic(message.message);

      // scroll to bottom or highlight the tab
      if (this.elem.hasClassName('active'))
        this.scrollToBottom();
      else if (message.event == "say" && message.highlight) {
        this.tab.addClassName("highlight");
        growlNotify(message);
      }
      else if (message.event == "say")
        this.tab.addClassName("unread");
    }
    else if (message.event == "announce") {
      this.messages.insert("<li class='message'><div class='msg announce'>"+message.str+"</div></li>");
    }

    var messages = $$('#' + message.chanid + ' li');
    if (messages.length > 250) messages.first().remove();
  },
  
  scrollToBottom: function (force) {
    this.elem.scrollTop = this.elem.scrollHeight;
  }
});
