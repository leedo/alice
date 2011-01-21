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
      if (hours >= 12) {
        if (hours > 12) hours -= 12;
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
          setTimeout(function () {popup.cancel();}, 5000);
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
    image.style.display = 'inline';
    image.style.visibility = 'visible';
    setTimeout(function () {
      var messagelist = image.up(".messages");
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
  },

  tabsets: {
    addSet: function () {
			var name = prompt("Please enter a name for this tab set.");
      if (name && !Alice.tabsets.hasTabset(name)) {
        Alice.tabsets.clearActive();
        $('sets').insert('<li class="active">'+name.escapeHTML()+'</li>');
        var list = $('empty_tabset').clone(true).addClassName('active').show();
        list.id = null;
        $('tabset_data').insert(list);
      }
      else {
        alert("Invalid tab set name.");
      }
    },

    hasTabset: function (name) {
      var sets = $$('#sets li');
      for (var i=0; i < sets.length; i++) {
        if (sets[i].innerHTML == name) {
          return true;
        }
      }
      return false;
    },

    submit: function (params) {
      new Ajax.Request("/savetabsets", {
        method: "post",
        parameters: Object.toQueryString(params),
        onSuccess: function(transport){
          $('tabset_menu').replace(transport.responseText);
          Alice.tabsets.remove()
        }
      });
      return false;
    },

    params: function () {
      var values = Alice.tabsets.values();
      return Alice.tabsets.sets().inject({}, function(acc, set, index) {
        acc[set] = values[index];
        return acc;
      });
    },

    sets: function () {
      if (!$('sets')) return [];
      return $('sets').select('li').map(function(li) {return li.innerHTML});
    },

    values: function () {
      if (!$('tabset_data')) return [];

      return $$('#tabset_data ul').map(function(ul) {
        var windows = ul.select('input').filter(function(input) {
          return input.checked;
        }).map(function(input){return input.name});
        return windows.length ? windows : 'empty';
      });
    },

    remove: function () {
      alice.input.disabled = false;
      $('tabsets').remove();
    },

    clearActive: function () {
      $('tabset_data').select('.active').invoke('removeClassName', 'active');
      $('sets').select('.active').invoke('removeClassName', 'active');
    },

    removeSet: function () {
      $('tabsets').down('.active').remove();
      $('tabset_data').down('.active').remove();
    },

    focusIndex: function (i) {
      Alice.tabsets.clearActive();
      $('tabset_data').select('ul')[i].addClassName('active');
      $('sets').select('li')[i].addClassName('active');
    },

    focusSet: function (e) {
      var li = e.findElement('li');
      if (li) {
        Alice.tabsets.focusIndex(li.previousSiblings().length);
      }
    },
  },

  prefs: {
    addHighlight: function (alias) {
		  var channel = prompt("Enter a word to highlight.");
		  if (channel)
		    $('highlights').insert("<option value=\""+channel+"\">"+channel+"</option>");
		  return false;
		},

    removeHighlights: function (alias) {
		  $A($('highlights').options).each(function (option) {
		    if (option.selected) option.remove()});
		  return false;
		},

    addNick: function (nick) {
      var nick = prompt("Enter a nick.");
      if (nick)
        $('monospace_nicks').insert("<option value=\""+nick+"\">"+nick+"</option>");
      return false;
    },

    removeNicks: function (nick) {
      $A($('monospace_nicks').options).each(function (option) {
        if (option.selected) option.remove()});
      return false;
    },

    remove: function() {
      alice.input.disabled = false;
      $('prefs').remove();
    },

    submit: function(form) {
      var options = {highlights: [], monospace_nicks: []};

      ["images", "avatars", "alerts"].each(function (pref) {
        options[pref] = $(pref).checked ? "show" : "hide";
      });
      $A($("highlights").options).each(function(option) {
        options.highlights.push(option.value);
      });

      $A($("monospace_nicks").options).each(function(option) {
        options.monospace_nicks.push(option.value);
      });

      ["style", "timeformat"].each(function(pref) {
        options[pref] = $(pref).value;
      });

			alice.options = options;

      new Ajax.Request('/save', {
        method: 'get',
        parameters: options,
        onSuccess: function(){Alice.prefs.remove()}
      });

      return false;
    }
  },

  connections: {
    disconnectServer: function (alias) {
		  $(alias + "_status").className = "disconnected";
		  $(alias + "_status").innerHTML = "disconnected";
		  $(alias + "_connection").innerHTML = "connect";
		  $(alias + "_connection").onclick = function (e) {
		    e.stop();
		    serverConnection(alias, "connect");
		  };
		},

    connectServer: function (alias) {
		  $(alias + "_status").className = "connected";
		  $(alias + "_status").innerHTML = "connected";
		  $(alias + "_connection").innerHTML = "disconnect";
		  $(alias + "_connection").onclick = function (e) {
		    e.stop();
		    serverConnection(alias, "disconnect");
		  };
		},

    showConnection: function (alias) {
		  $$("div#servers .active").invoke("removeClassName","active");
			$("setting_" + alias).addClassName("active");
			$("menu_" + alias).addClassName("active");
	  },
		
    addChannel: function (alias) {
			var channel = prompt("Please enter a channel name.");
			if (channel)
			  $("channels_" + alias).insert("<option value=\""+channel+"\">"+channel+"</option>");
			return false;
	  },

    addCommand: function (alias) {
			var command = prompt("Please enter a command.");
			if (command)
			  $("on_connect_" + alias).insert("<option value=\""+command+"\">"+command+"</option>");
			return false;
		},

    removeCommands: function (alias) {
			$A($("on_connect_" + alias).options).each(function (option) {
			if (option.selected) option.remove()});
			  return false;
		},

    removeChannels: function (alias) {
			$A($("channels_" + alias).options).each(function (option) {
			if (option.selected) option.remove()});
			  return false;
		},

    addServer: function () {
			var name = prompt("Please enter a name for this server.");
			if (! name) return;
			// TODO: test if this server is already being used ...
			new Ajax.Request("/serverconfig", {
			  parameters: {name: name},
			  method: 'get',
			  onSuccess: function (trans) {
			    var data = trans.responseText.evalJSON();
			    $$('#config_data div.setting').invoke('removeClassName',"active");
			    $$('#servers li').invoke('removeClassName',"active");
			    $('config_data').insert(data.config);
			    $('connections').insert(data.listitem);
			  }
		  });
	  },

    removeServer: function () {
		  var alias = $('connections').down('.active').id.replace(/^menu_/, "");
			if (alias && confirm("Are you sure you want to remove "+alias+"?")) {
			  $("menu_"+alias).remove();
			  $("setting_"+alias).remove();
			  $("connections").down("li", 1).addClassName("active");
			  $("config_data").down("div").addClassName("active");
			}
	  },

    submit: function(form) {
      $$('#servers .channelselect').each(function(select) {
        $A(select.options).each(function(option) {
          option.selected = true;
        });
      });

      new Ajax.Request('/save', {
        method: 'post',
        parameters: form.serialize(),
        onSuccess: function(){Alice.connections.remove()}
      });

      return false;
    },

    remove: function() {
      alice.input.disabled = false;
      $('servers').remove();
    },

    serverConnection: function(alias, action) {
      new Ajax.Request('/say', {
        method: 'get',
        parameters: {
          msg: '/' + action + ' ' + alias,
          source: alice.activeWindow().id
        }
      });

      return false;
    }
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
