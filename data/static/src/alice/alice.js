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
    this.channels = [];
    this.channelLookup = [];
    this.previousFocus = 0;
    this.connection = new Alice.Connection;
    this.filters = [ this.linkFilter ];
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
    this.channelLookup[channel.id] = this.channels.length;
    this.channels.push(channel);
  },
  
  removeChannel: function (channel) {
    if (channel.active) alice.focusLast();
    alice.channels.splice(alice.channelLookup[channel.id], 1);
    alice.channelLookup[channel.id] = null;
    alice.connection.partChannel(channel);
  },
  
  getChannel: function (channelId) {
    return this.channels[this.channelLookup[channelId]];
  },
  
  activeChannel: function () {
    for (var i=0; i < this.channels.length; i++) {
      if (this.channels[i].active) return this.channels[i];
    }
    return this.channels[0];
  },
  
  onKeyUp: function (e) {
    switch (e.which) {
      case 17:
        this.isCtrl = false;
        break;
      case 91:
        this.isCommand = false;
        break;
      case 18:
        this.isAlt = false;
        break;
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
      $$('.channel.active .messages').first().innerHTML = '';
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
    for (var i=0; i < this.channels.length; i++) {
      if (i + 1 < this.channels.length && this.channels[i].active) {
        this.previousFocus = i;
        this.channels[i + 1].focus();
        return;
      }
      else if (i + 1 >= this.channels.length) {
        this.previousFocus = i;
        this.channels[0].focus();
        return;
      }
    }
  },
  
  focusLast: function () {
    this.channels[this.previousFocus].focus();
  },
  
  previousTab: function () {
    for (var i=this.channels.length - 1; i >= 0; i--) {
      if (i > 0 && this.channels[i].active) {
        this.previousFocus = i;
        this.channels[i - 1].focus();
        return;
      }
      else if (i <= 0) {
        this.previousFocus = i;
        this.channels[this.channels.length - 1].focus();
        return;
      }
    }
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
})
window.onkeydown = function () {
  if (! alice.isCtrl && ! alice.isCommand && ! alice.isAlt)
    alice.activeChannel().input.focus()};
window.onresize = function () {
  alice.activeChannel().scrollToBottom()};
window.status = " ";
