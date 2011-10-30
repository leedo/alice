Object.extend(Alice, {
  RE: { 
    img: /^http[^\s]*\.(?:jpe?g|gif|png|bmp|svg)[^\/]*$/i,
    audio: /^http[^\s]*\.(?:wav|mp3|ogg|aiff?|m4[ar])[^\/]*$/i,
    url: /(https?:\/\/[^\s<"']*)/ig
  },

  cleanupCopy: function(node) {
    if (!node.select("li.message").length) return;

    var lines = [];
    node.select("li.message").each(function(line) {
      var left = line.down("div.left span.nick");
      var message = line.down("div.msg");
      var clean = [];
      if (left) {
        var nick = left.innerHTML.stripTags();
        nick = nick.replace(/^\s+/, "");
        nick = nick.replace(/\s+$/, "");
        clean.push("<"+nick+">");
      }
      if (message) {
        var body = message.innerHTML.stripTags();
        body = body.replace(/^\s+/, "");
        body = body.replace(/\s+$/, "");
        clean.push(body);
      }
      if (clean.length) lines.push(
        clean.join(" ").replace(/\n/g, "").escapeHTML());
    });
    node.update(lines.join("<br>"));
    node.cleanWhitespace();
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

  makeLinksClickable: function(elem) {
    var children = elem.childNodes;
    var length = children.length;

    for (var i=0; i < length; i++) {
      var node = children[i];
      if (node.nodeName != "#text") {
        Alice.makeLinksClickable(node);
      }
      else if (node.nodeValue.match(Alice.RE.url)) {
        var span = new Element("SPAN");
        span.innerHTML = node.nodeValue.escapeHTML().replace(
          Alice.RE.url, '<a href="$1" target="_blank" rel="noreferrer">$1</a>');
        node.parentNode.replaceChild(span, node);
      }
    }
  },

  growlNotify: function(message) {
    if (window.fluid) {
      window.fluid.showGrowlNotification({
        title: message.subject, 
        description: message.body,
        priority: 1, 
        sticky: false,
        identifier: message.msgid
      });
    }
    else if (window.webkitNotifications) {
      if (window.webkitNotifications.checkPermission() == 0) {
        var popup = window.webkitNotifications.createNotification(
          "http://static.usealice.org/image/alice.png",
          message.subject,
          message.body
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
			40,17,18,91,112,113,114,115,116,117,118,119,120,121,122,123,
      224
		];
		return special_keys.indexOf(keyCode) > -1;
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
      return $('sets').select('li').map(function(li) {return li.innerHTML.unescapeHTML()});
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

      ["images", "avatars", "alerts", "audio"].each(function (pref) {
        options[pref] = $(pref).checked ? "show" : "hide";
      });
      $A($("highlights").options).each(function(option) {
        options.highlights.push(option.value);
      });

      $A($("monospace_nicks").options).each(function(option) {
        options.monospace_nicks.push(option.value);
      });

      ["style", "timeformat", "quitmsg"].each(function(pref) {
        options[pref] = $(pref).value;
      });

      Alice.prefs.remove();

			new Ajax.Request('/save', {
        method: 'get',
        parameters: options,
        onSuccess: function(){
          var reload = (alice.options.avatars != options.avatars || 
                        alice.options.images != options.images ||
                        alice.options.style != options.style);

          if (reload) {
            window.location.reload();
          }
          else {
            alice.options = options;
            if (window.location.toString().match(/safe/i)) {
              alice.options.avatars = "hide";
              alice.options.images = "hide";
            }
          }
        }
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
		    Alice.connections.serverConnection(alias, "connect");
		  };
		},

    connectServer: function (alias) {
		  $(alias + "_status").className = "connected";
		  $(alias + "_status").innerHTML = "connected";
		  $(alias + "_connection").innerHTML = "disconnect";
		  $(alias + "_connection").onclick = function (e) {
		    e.stop();
		    Alice.connections.serverConnection(alias, "disconnect");
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
			    $$('#config_data table').invoke('removeClassName',"active");
			    $$('#connections li').invoke('removeClassName',"active");
			    $('config_data').down('.config_body').insert(data.config);
			    $('connections').insert(data.listitem);
			  }
		  });
	  },

    removeServer: function () {
		  var alias = $('connections').down('.active').id.replace(/^menu_/, "");
			if (alias && confirm("Are you sure you want to remove "+alias+"?")) {
			  $("menu_"+alias).remove();
			  $("setting_"+alias).remove();
			  $("connections").down("li").addClassName("active");
			  $("config_data").down("table").addClassName("active");
			}
	  },

    submit: function(form) {
      var params = form.serialize(true);
      form.select(".channelselect").each(function(select) {
        params[select.name] = $A(select.options).map(function(opt){return opt.value});
      });

      new Ajax.Request('/save', {
        method: 'post',
        parameters: params,
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
