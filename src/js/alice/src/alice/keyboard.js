Alice.Keyboard = Class.create({
  initialize: function(application) {
    this.application = application;
    this.isMac = navigator.platform.match(/mac/i);
    this.enable();
    
    this.shortcut("Cmd+C", { propagate: true });
    this.shortcut("Ctrl+C", { propagate: true });
    this.shortcut("Cmd+K");
    this.shortcut("Cmd+B");
    this.shortcut("Cmd+F");
    this.shortcut("Opt+Up");
    this.shortcut("Opt+Down");
    this.shortcut("Opt+Enter");
    this.shortcut("Cmd+Shift+M");
    this.shortcut("Cmd+Shift+J");
    this.shortcut("Cmd+Shift+K");
    this.shortcut("Cmd+Shift+H");
    this.shortcut("Enter");
    this.shortcut("Esc");
    this.shortcut("Tab");
    for (var i = 0; i < 10; i++) {
      this.shortcut("Cmd+"+i);
      if (!this.isMac) this.shortcut("Opt+"+i);
    }
  },
  
  shortcut: function(name, options) {

    // use control as command on non-Mac platforms
    var meta = this.isMac ? "Meta" : "Ctrl";

    var keystroke = name.replace("Cmd", meta).replace("Opt", "Alt"), 
        method = "on" + name.replace(/\+/g, "");

    window.shortcut.add(keystroke, function(event) {
      if (this.enabled) {
        this.activeWindow = this.application.activeWindow();
        if (method.match(/\d$/)) {
          this.onNumeric.call(this, event, method.substr(-1));
        }
        else {
          this[method].call(this, event);
        }
        delete this.activeWindow;
      }
    }.bind(this), options);
  },

  onNumeric: function(event, number) {
    var win = this.application.nth_window(number);
    if (win) win.focus();
  },

  onCmdC: function(event) {
    if (!this.activeWindow.input.focused)
      this.activeWindow.input.cancelNextFocus();
  },

  onCtrlC: function(event) {
    this.onCmdC(event);
  },

  onCmdK: function() {
    this.activeWindow.messages.down("ul").update("");
    this.activeWindow.lastNick = "";
  },
  
  onCmdShiftM: function() {
    this.application.windows().invoke('markRead');
  },
  
  onCmdShiftJ: function() {
    this.activeWindow.scrollToBottom(1);
  },
  
  onCmdShiftK: function() {
    this.activeWindow.toggleNicks();
  },

  onCmdShiftH: function() {
    this.application.toggleHelp();
  },
  
  onCmdB: function() {
    this.application.previousWindow();
  },
  
  onCmdF: function() {
    this.application.nextWindow();
  },
  
  onOptUp: function() {
    this.activeWindow.input.previousCommand();
  },
  
  onOptDown: function() {
    this.activeWindow.input.nextCommand();
  },
  
  onOptEnter: function() {
    this.activeWindow.input.newLine();
  },
  
  onEnter: function() {
    this.activeWindow.input.send();
  },
  
  onTab: function() {
    this.activeWindow.input.completeNickname();
  },
  
  onEsc: function() {
    this.activeWindow.input.stopCompletion();
  },
  
  enable: function() {
    this.enabled = true;
  },
  
  disable: function() {
    this.enabled = false;
  }
});
