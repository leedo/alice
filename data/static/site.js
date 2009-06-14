var filters = [
  function (content) {
    var filtered = content;
    // links
    filtered = filtered.replace(
      /(https?\:\/\/.+?)([\b\s<])/gi,
      "<a href=\"$1\" target=\"blank\">$1</a>$2");
    // images
    filtered = filtered.replace(
      /(<a[^>]*>)(.*?(:?jpg|jpeg|gif|png))/gi,
      "$1<img src=\"$2\" onload=\"loadInlineImage(this)\" />");
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
  console.log(audio);
  image.src = '/static?f=pause.png'; 
  if (! audio) {
      var url = image.nextSibling.href;
      audio = new Audio(url);
      console.log(audio);
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

document.observe('dom:loaded', function () {
  var len = 0;
  new Ajax.Request('/stream', {
    method: 'get',
    onInteractive: function (transport) {
      var data = transport.responseText.slice(len).evalJSON();
      console.log(transport.responseText);
      len = transport.responseText.length;
      data.msgs.each(function(message) {
        message.channel = message.channel.replace('#', 'chan_');
        if (message.html.length > 0) {
          $(message.channel + '_messages').insert(applyFilters(message.html));
          if ($(message.channel).hasClassName('active'))
            scrollToBottom();
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
      })
    }
  });
});
window.onresize = scrollToBottom;