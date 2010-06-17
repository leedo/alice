Alice.Input = Class.create({
  initialize: function(win, element) {
    this.window = win;
    this.application = this.window.application;
    this.textarea = $(element);
    this.editor = WysiHat.Editor.attach(this.textarea);
    this.element = this.editor ? this.editor : this.textarea;

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

  setValue: function(value) {
    if (this.editor) {
      this.editor.update(value);
    }
    this.textarea.setValue(value);
  },

  getValue: function() {
    if (this.editor) {
      return this.editor.innerHTML;
    }
    return this.textarea.getValue();
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

    // hack to focus an empty editor...
    if (this.editor && this.editor.innerHTML == "") {
      this.editor.appendChild(document.createTextNode(""));
      window.getSelection().selectNode(this.editor.childNodes[0]);
    }
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
    this.application.connection.sendMessage(this.textarea.form);
    this.history.push(this.getValue());
    this.setValue("");
    if (this.editor) this.editor.update();
    this.index = -1;
    this.stash();
    this.update();
    this.focus();
  },
  
  completeNickname: function() {
    if (!this.completion) {
      this.completion = new Alice.Completion(this, this.window.getNicknames());
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
    this.buffer = this.getValue();
  },
  
  update: function() {
    this.setValue(this.getCommand(this.index));
  },
  
  getCommand: function(index) {
    if (index == -1) {
      return this.buffer;
    } else {
      return this.history[index];
    }
  },
  
  resize: function() {
    if (this.editor) {
      this.textarea.setValue(this.editor.innerHTML);
    }
    (function() {
      if (!this.window.active) return;
      var height = this.getContentHeight();
      if (height == 0) {
        this.element.setStyle({ height: null, top: 0 });
      } else if (height <= 150) {
        this.element.setStyle({ height: height + "px", top: "-1px" });
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

    var value = this.getValue();
    element.update(value.replace(/\n$/, "\n\n").replace("\n", "<br>"));
    $(document.body).insert(element);

    var height = element.getHeight();
    element.remove();
    return height;
  }
});
