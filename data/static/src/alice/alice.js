//= require <prototype>
//= require <scriptaculous>
//= require <scriptaculous/effects>
//= require <scriptaculous/controls>
//= require <scriptaculous/dragdrop>

var Alice = Class.create({
  initialize: function () {
    this.isCtrl = false;
    this.isCommand = false;
    this.isAlt = false;
    this.isFocused = true;
    this.channels = new Hash();
    this.previousFocus = 0;
    this.connection = new Alice.Connection;
    this.filters = [ this.linkFilter ];
    this.monospaceNicks = ['Shaniqua', 'root', 'p6eval'];
    document.onkeyup = this.onKeyUp.bind(this);
    document.onkeydown = this.onKeyDown.bind(this);
    setTimeout(this.connection.connect.bind(this.connection), 1000);
  },
  
  toggleConfig: function (e) {
    if (! $('config')) {
      this.connection.getConfig(function (transport) {
          $('container').insert(transport.responseText);
        });
    }
    else {
      $('config').remove();
      $$('.overlay').invoke('remove');
    }
  },
  
  submitConfig: function(form) {
    $$('#config .channelselect').each(function (select) {
      $A(select.options).each(function (option) {
        option.selected = true;
      });
    });
    this.connection.sendConfig(form.serialize());
    $('config').remove();
    $$('.overlay').invoke('remove');
    return false;
  },
  
  addChannel: function (channel) {
    this.channels.set(channel.id, channel);
  },
  
  removeChannel: function (channel) {
    if (channel.active) this.focusLast();
    this.channels.unset(channel.id);
    this.connection.partChannel(channel);
    channel = null;
  },
  
  getChannel: function (channelId) {
    return this.channels.get(channelId);
  },
  
  activeChannel: function () {
    var channels = this.channels.values();
    for (var i=0; i < channels.length; i++) {
      if (channels[i].active) return channels[i];
    }
  },
  
  onKeyUp: function (e) {
    if (e.which != 75 && e.which != 78 && e.which != 80) {
      this.isCtrl = false;
      this.isCommand = false;
      this.isAlt = false; 
    }
  },
  
  onKeyDown: function (e) {
    if (e.which == 17)
      this.isCtrl = true;
    else if (e.which == 91)
      this.isCommand = true;
    else if (e.which == 18)
      this.isAlt = true;
    else if (this.isCtrl && e.which == 75) {
      this.activeChannel().messages.innerHTML = '';
      return false;
    }
    else if (this.isCtrl && e.which == 78) {
      this.nextTab();
      return false;
    }
    else if (this.isCtrl && e.which == 80) {
      this.previousTab();
      return false;
    }
    else if (e.which == Event.KEY_UP) {
      this.activeChannel().previousMessage();
    }
    else if (e.which == Event.KEY_DOWN) {
      this.activeChannel().nextMessage();
    }
  },
  
  linkFilter: function (content) {
    var filtered = content;
    filtered = filtered.replace(
      /(https?\:\/\/[\w\d$\-_.+!*'(),%\/?=&;~#:@]*)/gi,
      "<a href=\"$1\">$1</a>");
    return filtered;
  },
  
  addFilters: function (list) {
    this.filters = this.filters.concat(list);
  },
  
  applyFilters: function (content) {
    this.filters.each(function(filter) {
        content = filter(content);
      });
    return content;
  },
  
  nextTab: function () {
    var nextChan = this.activeChannel().tab.next();
    if (! nextChan)
      nextChan = $$('.channel').first();
    if (! nextChan) return;
    nextChan = nextChan.id.replace('_tab','');
    this.getChannel(nextChan).focus();
  },
  
  focusLast: function () {
    if (this.previousFocus)
      this.previousFocus.focus();
    else if (this.channels.values().length)
      this.channels.values().first().focus();
  },
  
  previousTab: function () {
    var prevChan = this.activeChannel().tab.previous();
    if (! prevChan)
      prevChan = $$('.channel').last();
    if (! prevChan) return;
    prevChan = prevChan.id.replace('_tab','');
    this.getChannel(prevChan).focus();
  },
  
  closeTab: function (chanid) {
    var channel = this.getChannel(chanid);
    if (channel) channel.close();
  },
  
  addTab: function (chan, html) {
    chan = $(chan);
    if (! chan) {
      $('channels').insert(html.channel);
      $('tabs').insert(html.tab);
    }
  },
  
  handleActions: function (list) {
    var self = this;
    list.each(function(action) {
      self.handleAction(action);
    });
  },
  
  handleAction: function (action) {
    switch (action.event) {
      case "join":
        this.addTab(action.chanid, action.html);
        break;
      case "part":
        this.closeTab(action.chanid);
        break;
    }
  },
  
  displayMessages: function (list) {
    var self = this;
    list.each(function(message) {
      self.displayMessage(message);
    });
  },
  
  displayMessage: function (message) {
    var channel = alice.getChannel(message.chanid);
    if (! channel) {
      this.connection.requestTab(message.chan, message.session, message);
      return;
    }
    channel.addMessage(message);
  }
});

//= require <alice/channel>
//= require <alice/connection>
//= require <alice/autocompleter>
//= require <alice/util>

var alice = new Alice();

document.observe("dom:loaded", function () {
  $$("div.topic").each(function (topic){
    topic.innerHTML = alice.linkFilter(topic.innerHTML)});
  $('config_button').observe("click", alice.toggleConfig.bind(alice));
  alice.activeChannel().input.focus()
  window.onkeydown = function () {
    if (! $('config') && ! alice.isCtrl && ! alice.isCommand && ! alice.isAlt)
      alice.activeChannel().input.focus()};
  window.onresize = function () {
    alice.activeChannel().scrollToBottom()};
  window.status = " ";  
  window.onfocus = function () {
    alice.activeChannel().input.focus();
    alice.isFocused = true};
  window.onblur = function () {alice.isFocused = false};
});
