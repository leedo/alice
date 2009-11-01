var options = {
  images: 'show'
};

var js = /default\.js\?(.*)?$/;
$$('head script[src]').findAll(function(s) {
    return s.src.match(js);
}).each(function(s) {
  var params = s.src.match(js)[1];
  params.split("&").each(function(o) {
    var kv = o.split("=");
    options[kv[0]] = kv[1];
  });
}); 

alice.options = options;

alice.addFilters([
  function(content) {
    var filtered = content;
    filtered = filtered.replace(
      /(<a href=\"(:?.*?\.(:?wav|mp3|ogg|aiff))")/gi,
      "<img src=\"/static/styles/default/image/play.png\" " +
      "onclick=\"playAudio(this)\" class=\"audio\"/>$1");
    return filtered;
  },
  function (content) {
    var filtered = content;
    if (alice.options.images == "show") {
      filtered = filtered.replace(
        /(<a[^>]*>)([^<]*\.(:?jpe?g|gif|png|bmp|svg)(:?\?v=0)?)</gi,
        "$1<img src=\"$2\" onload=\"loadInlineImage(this)\" " +
        "alt=\"Loading Image...\" title=\"$2\" style=\"visibility:hidden\"/><");
    }
    return filtered;
  }
]);

function loadInlineImage(image) {
  var maxWidth = arguments.callee.maxWidth || 300;
  var maxHeight = arguments.callee.maxHeight || 300;
  image.style.visibility = 'hidden';
  console.log(image.height + " " + image.width);
  if (image.height > image.width && image.height > maxHeight) {
    image.style.width = 'auto';
    image.style.height = maxHeight + 'px';
  }
  else if (image.width > maxWidth) {
    image.style.height = 'auto';
    image.style.width = maxWidth + 'px';
  }
  else {
    image.style.height = 'auto';
  }
  image.style.visibility = 'visible';
  setTimeout(function () {
    var messagelist = image.up("ul.messages");
    messagelist.scrollTop = messagelist.scrollHeight;
  }, 50);
}

function playAudio(image, audio) {
  image.src = '/static/styles/default/image/pause.png'; 
  if (! audio) {
    var url = image.nextSibling.href;
    audio = new Audio(url);
    audio.addEventListener('ended', function () {
      image.src = '/static/styles/default/image/play.png';
      image.onclick = function () { playAudio(image, audio) };
    });
  }
  audio.play();
  image.onclick = function() {
    audio.pause();
    this.src = '/static/styles/default/image/play.png';
    this.onclick = function () { playAudio(this, audio) };
  };
}
