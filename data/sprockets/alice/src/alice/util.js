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
        title: message.chan + ": " + message.nick,
        description: message.message, 
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
			27,9,32,13,8,145,20,144,19,45,36,46,35,33,34,37,38,39,
			40,17,18,91,112,113,114,115,116,117,118,119,120,121,122,123
		];
		if (special_keys.indexOf(keyCode) == -1) return false;
		return true;
  }
});
