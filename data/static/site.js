Buttescompleter = Class.create(Ajax.Autocompleter, {
  onKeyPress: function (event) {
    if(this.active)
      switch(event.keyCode) {
        case Event.KEY_TAB:
          this.markNext();
          this.render();
          Event.stop(event);
          scrollToBottom(true);
          return;
        case Event.KEY_RETURN:
          this.selectEntry();
          Event.stop(event);
        case Event.KEY_ESC:
          this.hide();
          this.active = false;
          Event.stop(event);
          return;
        case Event.KEY_LEFT:
          this.markPrevious();
          this.render();
          Event.stop(event);
          return;
        case Event.KEY_RIGHT:
          this.markNext();
          this.render();
          Event.stop(event);
          return;
        case Event.KEY_UP:
          Event.stop(event);
          return;
        case Event.KEY_DOWN:
          Event.stop(event);
          return;
      }
    else if (event.keyCode==Event.KEY_TAB) {
      this.active = true;
      this.show();
      Event.stop(event);
    }
    else
      if(event.keyCode==Event.KEY_RETURN ||
        (Prototype.Browser.WebKit > 0 && event.keyCode == 0)) return;
 
    this.changed = true;
    this.hasFocus = true;
 
    if(this.observer) clearTimeout(this.observer);
    this.observer =
      setTimeout(this.onObserverEvent.bind(this), this.options.frequency*1000);
  },
  render: function() {
    if(this.entryCount > 0) {
      for (var i = 0; i < this.entryCount; i++)
        this.index==i ?
          Element.addClassName(this.getEntry(i),"selected") :
          Element.removeClassName(this.getEntry(i),"selected");
      if(this.hasFocus) {
      // this is triggered by TAB in onKeyPress
      //this.show();
      //this.active = true;
      }
    } else {
      this.active = false;
      this.hide();
    }
  }
});

var len = 0;
var req;
var isCtrl = false;
var seperator = "--xbuttesfirex\n";

document.onkeyup = function (e) {
  if (e.which == 17) isCtrl = false;
};
document.onkeydown = function (e) {
  if (e.which == 17)
    isCtrl = true;
  else if (isCtrl && e.which == 75) {
    $$('.channel.active .messages').first().innerHTML = '';
    return false;
  }
  else if (isCtrl && e.which == 78) {
    nextTab();
    return false;
  }
  else if (isCtrl && e.which == 80) {
    previousTab();
    return false;
  }
};

function linkFilter (content) {
  var filtered = content;
  // links
  filtered = filtered.replace(
    /(https?\:\/\/.+?)([\b\s<\[\]\{\}"'])/gi,
    "<a href=\"$1\" target=\"blank\">$1</a>$2");
  return filtered;
}
var filters = [
  linkFilter,
  function (content) {
    var filtered = content;
    // images
    filtered = filtered.replace(
      /(<a[^>]*?>)(.*?\.(:?jpg|jpeg|gif|png))</gi,
      "$1<img src=\"$2\" onload=\"loadInlineImage(this)\" width=\"0\" alt=\"Loading Image...\" /><");
    // audio
    filtered = filtered.replace(
      /(<a href=\"(:?.*?\.(:?wav|mp3|ogg|aiff))")/gi,
      "<img src=\"/static?f=play.png\" onclick=\"playAudio(this)\" class=\"audio\"/>$1");
    return filtered;
  }
];

function applyFilters (content) {
  filters.each(function(filter) {
    content = filter(content);
  });
  return content;
};

function loadInlineImage(image) {
  var maxWidth = arguments.callee.maxWidth || 400;
  image.style.width = 'auto';
  image.style.visibility = 'hidden';
  if (image.width > maxWidth) image.style.width = maxWidth + 'px';
  image.style.visibility = 'visible';
  setTimeout(function () {scrollToBottom(true)}, 50);
}

function scrollToBottom (force) {
  var height = document.viewport.getHeight();
  var offset = document.viewport.getScrollOffsets().top;
  var scroll = $('container').getHeight();
  if ((height + offset) >= scroll || force)
    window.scrollTo(0, document.height);
}

function showChannel (channel) {
  document.title = channel;
  channel = $(channel);
  if (! channel) return;
  var tab = $(channel.id + "_tab");
  var input = $(channel.id + "_msg");
  var oldchannel = $$('div.channel.active').first();
  if (oldchannel) {
    oldchannel.removeClassName('active');
    $(oldchannel.id + "_tab").removeClassName('active');
  }
  tab.addClassName('active');
  tab.removeClassName("unread");
  tab.removeClassName("highlight");
  channel.addClassName('active');
  $$('#tabs li').invoke('removeClassName', 'leftof_active');
  if (tab.previous()) tab.previous().addClassName('leftof_active');
  scrollToBottom(true);
  input.focus();
};

function nextTab () {
  var channel = $$('div#channels div.channel.active').first().next();
  if (! channel) channel = $$('div#channels div.channel').first();
  showChannel(channel.id);
}

function previousTab () {
  var channel = $$('div#channels div.channel.active').first().previous();
  if (! channel) var channel = $$('div#channels div.channel').last();
  showChannel(channel.id);
}

function playAudio(image, audio) {
  image.src = '/static?f=pause.png'; 
  if (! audio) {
    var url = image.nextSibling.href;
    audio = new Audio(url);
    audio.addEventListener('ended', function () {
      image.src = '/static?f=play.png';
      image.onclick = function () { playAudio(image, audio) };
    });
  }
  audio.play();
  image.onclick = function() {
    audio.pause();
    this.src = '/static?f=play.png';
    this.onclick = function () { playAudio(this, audio) };
  };
}

function sayMessage (form) {
  new Ajax.Request('/say', {
    method: 'get',
    parameters: form.serialize(),
  });
  form.childNodes[3].value = '';
  return false;
}

function stripNick (html) {
  html = html.replace(/<div class="left">.*<\/div>/,'');
  return html;
}

function handleUpdate (transport) {
  var time = new Date();
  var data = transport.responseText.slice(len);
  var start, end;
  start = data.indexOf(seperator);
  if (start > -1) {
    start += seperator.length;
    end = data.indexOf(seperator, start);
    if (end == -1) return;
  }
  else return;
  len += (end + seperator.length) - start;
  data = data.slice(start, end);

  try {
    data = data.evalJSON();
  }
  catch (err) {
    console.log(err);
    return;
  }
  data.actions.each(function(action) {displayAction(action)});
  data.msgs.each(function(message) {displayMessage(message)});
  var lag = time / 1000 -  data.time;
  console.log(lag);
  if (lag > 10) {
    console.log("reconnecting...");
    connect();
  }
}

function displayAction (action) {
  if (action.type == "join")
    createTab(action.chan + action.session, action.html);
  else if (action.type == "part")
    closeTab(action.chan + action.session);
  else if (action.type == "announce")
    announceMsg(action.chan + action.session, action.str);
}

function displayMessage (message) {  
  message.chan = message.chan + message.session;
  if (! $(message.chan + "_messages")) {
    requestTab(message.chan_full, message.session, function () {
      //displayMessage(message);
  });
    return;
  }

  if (message.html || message.full_html) {
    var last_message = $$('#' + message.chan + ' .'
      + message.nick + ':last-child .msg').first();
    if ((message.nick == "Shaniqua" || message.nick == "root" || message.nick == "p6eval")
      && last_message) {
      var html = applyFilters(message.html);
      last_message.insert("<br />" + html);
    }
    else if (message.type == "message" && last_message) {
      var html = stripNick(applyFilters(message.full_html));
      $(message.chan + '_messages').insert(html);
    }
    else {
      var html = applyFilters(message.full_html);
      $(message.chan + '_messages').insert(html);
    }
    
    if (message.event == "topic") $(message.chan + "_topic").innerHTML = linkFilter(message.message);
    
    // scroll to bottom or highlight the tab
    if ($(message.chan).hasClassName('active'))
      scrollToBottom();
    else if (message.type == "message" && message.highlight)
      $(message.chan + "_tab").className = "highlight";
    else if (message.type == "message")
      $(message.chan + "_tab").className = "unread";
  }
}

function createTab (chan, html) {
  chan = $(chan);
  if (! chan) {
    $('channels').insert(html.channel);
    $('tabs').insert(html.tab);
  }
}

function announceMsg (chan, str) {
  if ($(chan)) {
    $(chan + "_messages").insert(
      "<li><div class='msg announce'>"+str+'</div></li>');
    scrollToBottom();
  }
}

function closeTab (chan) {
  chan = $(chan);
  if (chan) {
    if (chan.hasClassName('active')) {
      if (chan.previous())
        showChannel(chan.previous().id);
      else if (chan.next())
        showChannel(chan.next().id);
    }
    chan.remove();
    $(chan.id + "_tab").remove();
  }
}

function requestTab (chan, session, callback) {
  new Ajax.Request('/say', {
    method: 'get',
    parameters: {chan: chan, session: session, msg: "/window new"},
    onSuccess: function (trans) {
      handleUpdate(trans);
      callback();
    }
  });
}

function partChannel (chan, session, chanid) {
  new Ajax.Request('/say', {
    method: 'get',
    parameters: {chan: chan, session: session, msg: "/part"},
    onSuccess: function () {closeTab(chanid)}
  });
}

function connect () {
  len = 0;
  if (req && req.transport) req.transport.abort();
  req = null;
  req = new Ajax.Request('/stream', {
    method: 'get',
    onException: function (req, e) {
      console.log("connection got an error...");
      setTimeout(connect, 2000);
    },
    onInteractive: handleUpdate,
    onComplete: function () {
      setTimeout(connect, 2000);
    }
  });
}

document.observe('dom:loaded', function () {
  $$('.topic').each(function(topic) {
    topic.innerHTML = linkFilter(topic.innerHTML);
  });
  setTimeout(connect, 1000);
});
window.onresize = scrollToBottom;
