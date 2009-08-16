Alice.Input = Class.create({
  initialize: function(win, element) {
    this.window = win;
    this.application = this.window.application;
    this.element = $(element);
    this.history = [];
    this.index = -1;
    this.buffer = "";
  },
  
  focus: function() {
    this.element.focus();
  },
  
  previousCommand: function() {
    if (this.index-- == -1) {
      this.index = this.history.length - 1;
      this.stash();
    }

    this.update();
  },
  
  nextCommand: function() {
    if (this.index++ == -1) {
      this.stash();
    } else if (this.index == this.history.length) {
      this.index = -1;
    }

    this.update();
  },
  
  newLine: function() {
    console.log("newLine");
  },
  
  send: function() {
    this.application.connection.sendMessage(this.element.form);
    this.history.push(this.element.getValue());
    this.element.setValue("");
    this.index = -1;
    this.stash();
    this.update();
  },
  
  stash: function() {
    this.buffer = this.element.getValue();
  },
  
  update: function() {
    this.element.setValue(this.getCommand(this.index));
  },
  
  getCommand: function(index) {
    if (index == -1) {
      return this.buffer;
    } else {
      return this.history[index];
    }
  }
});
