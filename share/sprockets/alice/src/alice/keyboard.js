Alice.Keyboard = Class.create({
  initialize: function(application) {
    this.application = application;
    this.enable();
    
    this.shortcut("Cmd+C", { propagate: true });
    this.shortcut("Cmd+K");
    this.shortcut("Cmd+B");
    this.shortcut("Cmd+F");
    this.shortcut("Opt+Up");
    this.shortcut("Opt+Down");
    this.shortcut("Opt+Enter");
    this.shortcut("Cmd+Shift+M");
    this.shortcut("Cmd+Shift+J");
    this.shortcut("Cmd+Shift+K");
    this.shortcut("Enter");
    this.shortcut("Esc");
    this.shortcut("Tab");
  },
  
  shortcut: function(name, options) {
    var keystroke = name.replace("Cmd", "Meta").replace("Opt", "Alt"), 
        method = "on" + name.replace(/\+/g, "");

    window.shortcut.add(keystroke, function(event) {
      if (this.enabled) {
        this.activeWindow = this.application.activeWindow();
        this[method].call(this, event);
        delete this.activeWindow;
      }
    }.bind(this), options);
  },
  
  onCmdC: function(event) {
    if (!this.activeWindow.input.focused) {
      this.activeWindow.input.cancelNextFocus();
    }
  },

  onCmdK: function() {
    this.activeWindow.messages.update("");
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
