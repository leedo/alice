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
      /(<a[^>]*?>)(.*?(:?jpg|jpeg|gif|png))/gi,
      "$1<img src=\"$2\" onload=\"loadInlineImage(this)\" width=\"0\" alt=\"Loading Image...\" />");
    // audio
    filtered = filtered.replace(
      /(<a href=\"(.*?(:?wav|mp3|ogg|aiff)))/gi,
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
  setTimeout(scrollToBottom, 50);
}

function scrollToBottom () {
  var height = document.viewport.getHeight();
  var offset = document.viewport.getScrollOffsets().top;
  var scroll = $('container').getHeight();
  if ((height + offset) >= scroll)
    window.scrollTo(0, document.height);
}

function showChannel (channel) {
  document.title = channel.replace("chan_", "#");
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
  scrollToBottom();
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
  console.time('slice_buffer');
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
  var lag = time / 1000 -  data.time;
  console.log(lag);
  console.timeEnd('slice_buffer');
  console.time('insert_messages');
  data.msgs.each(function(message) {displayMessage(message)});
  console.timeEnd('insert_messages');
  console.time('insert_actions');
  data.actions.each(function(action) {displayAction(action)});
  console.timeEnd('insert_actions');
}

function displayAction (action) {
  if (action.type == "join")
    createTab(action.chan, action.html);
  else if (action.type == "part")
    closeTab(action.chan);
  else if (action.type == "announce")
    announceMsg(action.chan, action.str);
}

function displayMessage (message) {
  message.chan = message.chan.replace('#', 'chan_');
  if (message.html || message.full_html) {
    var last_message = $$('#' + message.chan + ' .'
      + message.nick + ':last-child .msg').first();
    if (message.nick == "Shaniqua" && last_message) {
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
    
    // pop off the oldest message
    if ($$(message.channel + "_messages li").length > 100)
      $$(message.chan + "_message li")[0].remove();
    
    console.log(message);
    // scroll to bottom or highlight the tab
    if ($(message.chan).hasClassName('active'))
      scrollToBottom();
    else if (message.highlight)
      $(message.chan + "_tab").className = "highlight";
    else if (! $(message.chan + "_tab").className)
      $(message.chan + "_tab").className = "unread";
  }
}

function createTab (chan, html) {
  chan = $(chan.replace("#", "chan_"));
  if (! chan) {
    $('channels').insert(html.channel);
    $('tabs').insert(html.tab);
  }
}

function announceMsg (chan, str) {
  chan = chan.replace("#", "chan_");
  if ($(chan)) {
    $(chan + "_messages").insert(
      "<li><div class='msg announce'>"+str+'</div></li>');
    scrollToBottom();
  }
}

function closeTab (chan) {
  chan = $(chan.replace("#", "chan_"));
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

function partChannel (chan) {
  chan = chan.replace("chan_", "#");
  new Ajax.Request('/say', {
    method: 'get',
    parameters: {chan: chan, msg: "/part"},
    onSuccess: function () {closeTab(chan)} 
  });
}

function connect () {
  len = 0;
  req = new Ajax.Request('/stream', {
    method: 'get',
    onException: function (req, e) {
      console.log(e);
      setTimeout(connect, 2000);
    },
    onInteractive: handleUpdate,
    onComplete: function () {
      setTimeout(connect, 2000);
    }
  });
}

document.observe('dom:loaded', function () {setTimeout(connect, 1000)});
window.onresize = scrollToBottom;
