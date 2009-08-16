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
  }
});
