Alice.Input = Class.create({
  initialize: function(win, element) {
    this.window = win;
    this.application = this.window.application;
    this.element = $(element);
    this.history = [];
    this.index = -1;
    this.buffer = "";
    this.completion = false;
    this.focused = false;
    
    this.element.observe("keypress", this.onKeyPress.bind(this));
    this.element.observe("blur", this.onBlur.bind(this));
    
    this.element.observe("keydown", this.resize.bind(this));
    this.element.observe("cut", this.resize.bind(this));
    this.element.observe("paste", this.resize.bind(this));
    this.element.observe("change", this.resize.bind(this));
  },
  
  onKeyPress: function(event) {
    if (event.keyCode != Event.KEY_TAB) {
      this.completion = false;
    }
  },
  
  cancelNextFocus: function() {
    this.skipThisFocus = true;
  },
  
  focus: function() {
    if (this.skipThisFocus) {
      this.skipThisFocus = false;
      return;
    }
    
    this.element.focus();
    this.focused = true;
  },
  
  onBlur: function() {
    this.focused = false;
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
  
  completeNickname: function() {
    if (!this.completion) {
      this.completion = new Alice.Completion(this.element, this.window.getNicknames());
    }

    this.completion.next();
  },
  
  stopCompletion: function() {
    if (this.completion) {
      this.completion.restore();
      this.completion = false;
    }
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
  },
  
  resize: function() {
    (function() {
      var height = this.getContentHeight();
      if (height == 0) {
        this.element.setStyle({ height: null });
      } else if (height <= 150) {
        this.element.setStyle({ height: height + "px" });
      }
    }).bind(this).defer();
  },
  
  getContentHeight: function() {
    var element = new Element("div").setStyle({
      position:   "absolute",
      visibility: "hidden",
      left:       "-" + this.element.getWidth() + "px",
      width:      this.element.getWidth() - 7 + "px",
      fontFamily: this.element.getStyle("fontFamily"),
      fontSize:   this.element.getStyle("fontSize"),
      lineHeight: this.element.getStyle("lineHeight"),
      whiteSpace: "pre-wrap",
      wordWrap:   "break-word"
    });

    var value = this.element.getValue().escapeHTML().replace("\n", "<br>");
    element.update(value);
    $(document.body).insert(element);

    var height = element.getHeight();
    element.remove();
    return height > 0 ? height - 1 : 0;
  }
});
