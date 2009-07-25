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

function stripNick (html) {
  html = html.replace(/<div class="left">.*<\/div>/,'');
  return html;
}

function growlNotify (message) {
  if (! window.fluid) return;
  window.fluid.showGrowlNotification({
      title: message.channel, 
      description: message.nick, 
      priority: 1, 
      sticky: false,
      identifier: message.session+message.channel+message.nick
  })
}