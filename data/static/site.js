var filters = [
  function (content) {
    var filtered = content;
    // links
    filtered = filtered.replace(
      /(https?\:\/\/.+?)([\b\s<])/gi,
      "<a href=\"$1\" target=\"blank\">$1</a>$2");
    // images
    filtered = filtered.replace(
      /(<a[^>]*?>)(.*?(:?jpg|jpeg|gif|png))/gi,
      "$1<img src=\"$2\" onload=\"loadInlineImage(this)\" />");
    // audio
    filtered = filtered.replace(
      /(<a href=\"(.*?(:?wav|mp3|ogg|aiff)))/gi,
      "<img src=\"/static?f=play.png\" onclick=\"playAudio(this)\" class=\"audio\"/>$1");
    return filtered;
  }
];
var len = 0;
var req;
var isCtrl = false;
var isError = false;

document.onkeyup = function (e) {
  if (e.which == 17) isCtrl = false;
}
document.onkeydown = function (e) {
  if (e.which == 17) {
    isCtrl = true;
  }
  if (isCtrl && e.which == 75) {
    $$('.channel.active .messages').first().innerHTML = '';
  }
}

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
  window.scrollTo(0, document.height);
}

function showChannel (channel) {
  var oldchannel = $$('div.channel.active').first();
  oldchannel.removeClassName('active');
  $(oldchannel.id + "_tab").removeClassName('active');
  $(channel).addClassName('active');
  $(channel + "_tab").addClassName('active');
  $$('#tabs li').invoke('removeClassName', 'leftof_active');
  if ($(channel + "_tab").previous())
    $(channel + "_tab").previous().addClassName('leftof_active');
  scrollToBottom();
  $(channel + '_msg').focus();
};

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

function handle_update (transport) {
  console.time('parse_responseText')
  var data = transport.responseText.slice(len);
  len = transport.responseText.length;
   
  // this isn't being stripped by FF for some reason...
  if (! Prototype.Browser.Safari) {
    data = data.replace(/--xbuttesfirex\n/g,"");
    data = data.replace("Content-Type: text/plain\r\n\r\n", ""); 
  }
  data = data.evalJSON();
  console.timeEnd('parse_responseText');
  
  console.time('inserting_html');
  data.msgs.each(function(message) {
    message.channel = message.channel.replace('#', 'chan_');
    if (message.html || message.full_html) {
      var last_message = $$('#' + message.channel + ' .'
        + message.nick + ':last-child .msg').first();
      if (message.nick == "Shaniqua" && last_message) {
        var html = applyFilters(message.html);
        last_message.insert("<br />" + html);
      }
      else if (message.type == "message" && last_message) {
        var html = stripNick(applyFilters(message.full_html));
        $(message.channel + '_messages').insert(html);
      }
      else {
        var html = applyFilters(message.full_html);
        $(message.channel + '_messages').insert(html);
      }
      if ($(message.channel).hasClassName('active')) scrollToBottom();
    }
  });
  data.actions.each(function(action) {
    if (action.type == "join") {
      var chan_clean = action.name.replace("#", "chan_");
      if (! $(chan_clean)) {
        $('container').insert(action.html.channel);
        $('tabs').insert(action.html.tab);
      }
    }
  });
  console.timeEnd('inserting_html');
}

function connect () {
  len = 0;
  console.log("connecting...");
  req = new Ajax.Request('/stream', {
    method: 'get',
    onException: function (req, e) {
      console.log(e);
      isError = true;
    },
    onComplete: function () {
      //if (! isError) { console.log('reconnecting now...');connect() }
      //else { console.log('reconnecting...');setTimeout(connect, 5000)}
    },
    onInteractive: handle_update
  });
}

document.observe('dom:loaded', connect);
window.onresize = scrollToBottom;