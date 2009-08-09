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
    this.lastNick = "";
    
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
      if (message.nick == this.lastNick) {
        if (alice.monospaceNicks.indexOf(message.nick) > -1)
          this.messages.down('li:last-child div.msg').insert(
            "<br>" + alice.applyFilters(message.html));
        else if (message.event == "say")
          this.messages.insert(
            stripNick(alice.applyFilters(message.full_html)));
      }
      else {
        if (message.event == "topic") {
          this.messages.insert(alice.linkFilter(message.full_html));
          this.displayTopic(message.message);
        }
        else {
          this.messages.insert(alice.applyFilters(message.full_html));
          this.lastNick = message.nick;
        }
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

    var messages = this.messages.childElements();
    if (messages.length > 250) messages.first().remove();
  },
  
  scrollToBottom: function (force) {
    if (! force) {
      var lastmsg = this.messages.childElements().last();
      if (! lastmsg) return;
      var msgheight = lastmsg.offsetHeight; 
      var bottom = this.elem.scrollTop + this.elem.offsetHeight;
      var height = this.elem.scrollHeight;
    }
    if (force || bottom + msgheight + 100 >= height)
      this.elem.scrollTop = this.elem.scrollHeight;
  }
});
