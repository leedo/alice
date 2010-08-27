Object.extend(Alice, {
  uncacheGravatar: function(content) {
    if (!this.timestamp) {
      var date = new Date();
      this.timestamp = date.getTime();
    }
    return content.replace(
      /(src=".*?gravatar.com\/avatar\/[^?]*\?)/gi,
      "$1time=" + this.timestamp + "&"
    ); 
  },

  epochToLocal: function(epoch, format) {
    var date = new Date(parseInt(epoch) * 1000);
    if (!date) return epoch;

    var hours = date.getHours();

    if (format == "12") {
      var ap;
      if (hours > 12) {
        hours -= 12;
        ap = "p";
      } else {
        ap = "a"
      }
      return sprintf("%d:%02d%s", hours, date.getMinutes(), ap);
    }

    return sprintf("%02d:%02d", hours, date.getMinutes());
  },
  
  stripNick: function(html) {
    return html.replace(/<div class="left">.*<\/div>/, '');
  },

  growlNotify: function(message) {
    if (window.fluid) {
      window.fluid.showGrowlNotification({
        title: message.window.title + ": " + message.nick,
        description: message.body.unescapeHTML(),
        priority: 1, 
        sticky: false,
        identifier: message.msgid
      });
    }
    else if (window.webkitNotifications) {
      if (window.webkitNotifications.checkPermission() == 0) {
        var popup = window.webkitNotifications.createNotification(
          "http://static.usealice.org/image/alice.png",
          message.window.title + ": " + message.nick,
          message.body.unescapeHTML()
        );

        popup.ondisplay = function() {
          setTimeout(function () {popup.cancel();}, 3000);
        };

        popup.show();
      }
    }
  },
  
  isSpecialKey: function(keyCode) {
    var special_keys = [
			16,27,9,32,13,8,145,20,144,19,45,36,46,35,33,34,37,38,39,
			40,17,18,91,112,113,114,115,116,117,118,119,120,121,122,123
		];
		return special_keys.indexOf(keyCode) > -1;
  },
  
  loadInlineImage: function(image) {
    var maxWidth = arguments.callee.maxWidth || 300;
    var maxHeight = arguments.callee.maxHeight || 300;
    image.style.visibility = 'hidden';
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
    image.style.display = 'block';
    image.style.visibility = 'visible';
    setTimeout(function () {
      var messagelist = image.up(".message_wrap");
      messagelist.scrollTop = messagelist.scrollHeight;
    }, 50);
  },

  playAudio: function(image, audio) {
    image.src = '/static/image/pause.png'; 
    if (! audio) {
      var url = image.nextSibling.href;
      audio = new Audio(url);
      audio.addEventListener('ended', function () {
        image.src = '/static/image/play.png';
        image.onclick = function () { Alice.playAudio(image, audio) };
      });
    }
    audio.play();
    image.onclick = function() {
      audio.pause();
      this.src = '/static/image/play.png';
      this.onclick = function () { Alice.playAudio(this, audio) };
    };
  }
});


Element.addMethods({
  redraw: function(element){
    element = $(element);
    var n = document.createTextNode(' ');
    element.appendChild(n);
    (function(){n.parentNode.removeChild(n)}).defer();
    return element;
  }
});
