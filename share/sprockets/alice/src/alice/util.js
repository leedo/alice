Object.extend(Alice, {
  makeLinksClickable: function(content) {
    return content.replace(
      /(https?\:\/\/[\w\d$\-_.+!*'(),%\/?=&;~#:@]*)/gi,
      "<a href=\"$1\">$1</a>"
    );
  },
  
  stripNick: function(html) {
    return html.replace(/<div class="left">.*<\/div>/, '');
  },

  growlNotify: function(message) {
    if (!window.fluid) return;
    window.fluid.showGrowlNotification({
        title: message.window.title + ": " + message.nick,
        description: message.body, 
        priority: 1, 
        sticky: false,
        identifier: message.msgid
    });
  },

  makeSortable: function() {
    Sortable.create('tabs', {
      overlap: 'horizontal',
      constraint: 'horizontal',
      format: /(.+)/,
      onUpdate: function (res) {
        var tabs = res.childElements();
        var order = tabs.collect(function(t){return t.id.match(/(?:win_)?(.+)_tab/)[1]});
        alice.connection.sendTabOrder(order);
        tabs.invoke('removeClassName','leftof_active');
        for (var i=0; i < tabs.length; i++) {
          if (tabs[i].hasClassName('active')) {
            if (tabs[i].previous()) tabs[i].previous().addClassName('leftof_active');
            tabs[i].removeClassName('leftof_active');
            return;
          }
        }
      }
    });
  },
  
  isSpecialKey: function(keyCode) {
    var special_keys = [
			16,27,9,32,13,8,145,20,144,19,45,36,46,35,33,34,37,38,39,
			40,17,18,91,112,113,114,115,116,117,118,119,120,121,122,123
		];
		return special_keys.indexOf(keyCode) > -1;
  },
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
