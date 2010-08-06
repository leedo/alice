Alice.Keyboard = Class.create({
  initialize: function(application) {
    this.application = application;
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
    this.shortcut("Enter");
    this.shortcut("Esc");
    this.shortcut("Tab");
    for (var i = 0; i < 10; i++) {
      this.shortcut("Cmd+"+i);
      this.shortcut("Opt+"+i);
    }
  },
  
  shortcut: function(name, options) {

    // use control as command on non-Mac platforms
    var meta = navigator.platform.match(/mac/i) ? "Meta" : "Ctrl";

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
    var windows = this.application.windows();
    if (windows[number]) windows[number].focus();
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
