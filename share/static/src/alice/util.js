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