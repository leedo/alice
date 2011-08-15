Alice.Input = Class.create({
  initialize: function(application, element) {

    this.application = application;
    this.textarea = $(element);
    this.disabled = false;

    if (this.canContentEditable()) {
      this.editor = WysiHat.Editor.attach(this.textarea);
      this.element = this.editor;
      this.toolbar = new Alice.Toolbar(this.element)
      this.toolbar.addButtonSet(Alice.Toolbar.ButtonSet);
      var input = new Element("input", {type: "hidden", name: "html", value: 1});
      this.textarea.form.appendChild(input);

      document.observe("mousedown", function(e) {
        if (!e.findElement(".editor")) this.uncancelNextFocus();
      }.bind(this));

      this.editor.observe("keydown", function(){this.cancelNextFocus()}.bind(this));
      this.editor.observe("keyup", this.updateRange.bind(this));
      this.editor.observe("mouseup", this.updateRange.bind(this));
      this.editor.observe("paste", this.pasteHandler.bind(this));

      this.toolbar.element.on("mouseup","button",function(){
        this.cancelNextFocus();
      }.bind(this));
    } else {
      this.element = this.textarea;
      this.element.observe("keydown", this.resize.bind(this));
      this.element.observe("cut", this.resize.bind(this));
      this.element.observe("paste", this.resize.bind(this));
      this.element.observe("change", this.resize.bind(this));
    }

    this.history = [];
    this.index = -1;
    this.buffer = "";
    this.completion = false;
    this.focused = false;
    this.focus();
    
    this.element.observe("blur", this.onBlur.bind(this));
  },

  setValue: function(value) {
    this.textarea.setValue(value);
    if (this.editor) {
      this.editor.update(value);
      // gross hack to work around some chrome redraw bug
      var text = document.createElement("BR");
      this.editor.appendChild(text);
    }
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
      this.element.stopObserving("keypress");
    }
  },
  
  uncancelNextFocus: function() {
    this.skipThisFocus = false;
  },

  cancelNextFocus: function() {
    this.skipThisFocus = true;
  },

  focus: function(force) {
    if (this.disabled) return;

    if (!force) {
      if (this.focused) return;

      if (this.skipThisFocus) {
        this.skipThisFocus = false;
        return;
      }
    }

    this.focused = true;

    // hack to focus the end of editor...
    if (this.editor) {
      var selection = window.getSelection();
      selection.removeAllRanges();
      if (this.range) {
        selection.addRange(this.range);
      } else {
        var text = document.createTextNode("");
        this.editor.appendChild(text);
        selection.selectNode(text);
        this.range = selection.getRangeAt(0);
      }
      this.editor.focus();
    } else {
      this.textarea.focus();
    }
  },
  
  onBlur: function(e) {
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
    this.application.log("newLine");
  },
  
  send: function() {
    var msg = this.getValue();

    if (msg.length > 1024*2) {
      alert("That message is way too long, dude.");
      return;
    }

    if (this.editor) this.textarea.value = msg;

    var success = this.application.connection.sendMessage(this.textarea.form);
    if (success) {
      this.history.push(msg);
      this.setValue("");
      if (this.editor) this.editor.update();
      this.index = -1;
      this.stash();
      this.update();
      this.focus(1);
    }
    else {
      alert("Could not send message, not connected!");
    }
  },
  
  completeNickname: function(prev) {
    if (this.disabled) return;
    if (!this.completion) {
      this.completion = new Alice.Completion(this.application.activeWindow().getNicknames(), this.editor);
      this.element.observe("keypress", this.onKeyPress.bind(this));
    }

    if (prev)
      this.completion.prev();
    else 
      this.completion.next();
  },
  
  stopCompletion: function() {
    if (this.completion) {
      this.completion.restore();
      this.completion = false;
      this.element.stopObserving("keypress");
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
    (function() {
      var height = this.getContentHeight();
      if (height == 0) {
        this.element.setStyle({ height: null, top: 0 });
      } else if (height <= 150) {
        this.element.setStyle({ height: height + "px", top: "0px" });
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

    // add classname so collapsed margins/paddings are applied
    if (this.editor) element.addClassName("editor");

    var value = this.getValue();
    element.update(value.replace(/\n$/, "\n\n").replace("\n", "<br>"));
    $(document.body).insert(element);

    var height = element.getHeight();
    element.remove();
    return height;
  },

  canContentEditable: function() {
    var element = new Element("div", {contentEditable: "true"});
    return  ! (element.contentEditable == null || this.application.isMobile || Prototype.Browser.IE || Prototype.Browser.Gecko);
  },

  updateRange: function (e) {
    var selection = window.getSelection();
    if (selection.rangeCount > 0) {
      var range = selection.getRangeAt(0);
      this.range = range;
    }
  },

  pasteHandler: function(e) {
    if (!e.clipboardData) return;

    var items = e.clipboardData.items;
    if (items) {
      var output = "";
      for (var i=0; i < items.length; i++) {
        var blob = items[i].getAsFile();
        if (blob && blob.type.match(/image/)) {
          e.stop();
          var fd = new FormData();
          fd.append("image", blob);
          fd.append("key", "f1f60f1650a07bfe5f402f35205dffd4");
          var xhr = new XMLHttpRequest();
          xhr.open("POST", "http://api.imgur.com/2/upload.json");
          xhr.onload = function() {
            var url = xhr.responseText.evalJSON();
            this.editor.insertHTML(url.upload.links.original);
            this.updateRange();
          }.bind(this);
          xhr.send(fd);
          return;
        }
      }
    }

    var text = e.clipboardData.getData("Text");
    if (text) {
      e.preventDefault();
      text = text.escapeHTML().replace(/\n+/g, "<br>\n");
      this.editor.insertHTML(text);
      this.updateRange();
      return;
    }

    var url = e.clipboardData.getData("URL");
    if (url) {
      e.preventDefault();
      this.editor.insertHTML(url);
      this.updateRange();
      return;
    }

  }
});
