function stripNick (html) {
  html = html.replace(/<div class="left">.*<\/div>/,'');
  return html;
}

function growlNotify (message) {
  if (! window.fluid) return;
  window.fluid.showGrowlNotification({
      title: message.chan + ": " + message.nick,
      description: message.message, 
      priority: 1, 
      sticky: false,
      identifier: message.msgid
  })
}

function makeSortable () {
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
