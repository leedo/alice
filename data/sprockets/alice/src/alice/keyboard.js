Alice.Keyboard = Class.create({
  initialize: function(application) {
    this.application = application;
    this.enable();
    
    this.shortcut("Cmd+K");
    this.shortcut("Cmd+B");
    this.shortcut("Cmd+F");
    this.shortcut("Opt+Up");
    this.shortcut("Opt+Down");
    this.shortcut("Opt+Enter");
    this.shortcut("Enter");
  },
  
  shortcut: function(name) {
    var keystroke = name.replace("Cmd", "Meta").replace("Opt", "Alt"), 
        method = "on" + name.replace("+", "");

    window.shortcut.add(keystroke, function() {
      if (this.enabled) {
        this.activeWindow = this.application.activeWindow();
        this[method].call(this);
        delete this.activeWindow;
      }
    }.bind(this));
  },
  
  onCmdK: function() {
    this.activeWindow.messages.update("");
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
  
  enable: function() {
    this.enabled = true;
  },
  
  disable: function() {
    this.enabled = false;
  }
});
