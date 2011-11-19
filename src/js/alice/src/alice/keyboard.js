Alice.Keyboard = Class.create({
  initialize: function(application) {
    this.application = application;
    this.isMac = navigator.platform.match(/mac/i);
    this.lastCycle = 0;
    this.cycleDelay = 300;
    this.enable();
    
    if (!this.application.isMobile) {
      this.shortcut("Cmd+C", { propagate: true });
      this.shortcut("Ctrl+C", { propagate: true });
      this.shortcut("Cmd+B");
      this.shortcut("Cmd+I");
      this.shortcut("Cmd+Shift+U");
      this.shortcut("Opt+Up");
      this.shortcut("Opt+Down");
      this.shortcut("Cmd+Shift+M");
      this.shortcut("Cmd+Shift+J");
      this.shortcut("Cmd+Shift+K");
      this.shortcut("Cmd+K");
      this.shortcut("Cmd+Shift+Left");
      this.shortcut("Cmd+Shift+Right");
      this.shortcut("Cmd+Shift+H");
      this.shortcut("Cmd+Shift+L");
      this.shortcut("Cmd+U");
      this.shortcut("Esc");
      this.shortcut("Cmd", { propagate: true });
      this.shortcut("Tab", { propagate: true });
      this.shortcut("Shift+Tab", { propagate: true });
      for (var i = 0; i < 10; i++) {
        this.shortcut("Cmd+"+i);
        if (!this.isMac) this.shortcut("Opt+"+i);
      }
    }

    this.shortcut("Enter");
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

  onCmd: function(e) {
    if (e.keyCode == 186) {
      e.stop();
      this.application.nextUnreadWindow();
    }
  },

  onNumeric: function(event, number) {
    var win = this.application.nth_window(number);
    if (number == 0) {
      win = this.application.info_window();
    }
    if (win) win.focus();
  },

  onCmdC: function(event) {
    this.application.input.cancelNextFocus();
  },

  onCtrlC: function(event) {
    this.onCmdC(event);
  },

  onCmdK: function() {
    this.activeWindow.messages.update("");
    this.activeWindow.lastNick = "";
    this.application.connection.sendMessage({
      msg: "/clear",
      source: this.activeWindow.id,
    });
  },

  onCmdB: function() {
    if (this.application.input.editor) {
      this.application.input.focus();
      this.application.input.editor.boldSelection();
    }
  },
  
  onCmdShiftU: function() {
    if (this.application.input.editor) {
      this.application.input.focus();
      this.application.input.editor.underlineSelection();
    }
  },

  onCmdI: function() {
    if (this.application.input.editor) {
      this.application.input.focus();
      this.application.input.editor.italicSelection();
    }
  },

  onCmdU: function() {
    this.application.nextUnreadWindow();
  },

  onCmdShiftM: function() {
    this.application.windows().invoke('markRead');
  },
  
  onCmdShiftJ: function() {
    this.activeWindow.scrollToBottom(1);
  },
  
  onCmdShiftK: function() {
    this.application.toggleOverlay();
  },

  onCmdRight: function() {
    this.application.nextWindow();
  },

  onCmdShiftL: function() {
    this.application.nextWindow();
  },

  onCmdShiftRight: function() {
    this.application.nextWindow();
  },
  
  onCmdLeft: function() {
    this.application.previousWindow();
  },

  onCmdShiftH: function() {
    this.application.previousWindow();
  },

  onCmdShiftLeft: function() {
    this.application.previousWindow();
  },
  
  onOptUp: function() {
    this.application.input.previousCommand();
  },
  
  onOptDown: function() {
    this.application.input.nextCommand();
  },
  
  onEnter: function() {
    this.application.input.send();
  },
  
  onTab: function(e) {
    if (!e.findElement('div.config')) {
      e.stop();
      this.application.input.completeNickname();
    }
  },

  onShiftTab: function(e) {
    if (!e.findElement('div.config')) {
      e.stop();
      this.application.input.completeNickname(true);
    }
  },

  onEsc: function() {
    this.application.input.stopCompletion();
  },
  
  enable: function() {
    this.enabled = true;
  },
  
  disable: function() {
    this.enabled = false;
  }
});
