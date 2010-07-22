
// override a few of the default toolbar methods
Alice.Toolbar = Class.create(WysiHat.Toolbar, {
  createButtonElement: function(toolbar, options) {
    var button = Element('button');
    button.update(options.get('label'));
    button.addClassName(options.get('name'));
    toolbar.appendChild(button);

    return button;
  },
  observeButtonClick: function(element, handler) {
    element.on('click', function(event) {

      // pass in the button and toolbar in addition
      // to the default editor parameter
      handler(this.editor, element, this);

      // need to fire this event to immediately toggle
      // the active class
      this.editor.fire("selection:change");

      event.stop();
    }.bind(this));
  }
});

Alice.Toolbar.ButtonSet = WysiHat.Toolbar.ButtonSets.Basic.concat(
  [
    {
      label: "Colors",
      handler: function (editor, button, toolbar) {
        var cb = function (color, fg) {
          fg ? editor.colorSelection(color) : editor.backgroundColorSelection(color)
        };
        if (toolbar.picker) {
          toolbar.picker.remove();
          toolbar.picker = undefined;
        } else {
          toolbar.picker = new Alice.Colorpicker(button, cb);
        }
      }
    },
    {
      label: "&raquo;",
      handler: function (editor, button, toolbar) {
        button.up("div.editor_toolbar").removeClassName("visible");
        if (toolbar.picker) {
          toolbar.picker.remove();
          toolbar.picker = undefined;
        }
      }
    }
  ]
);

Alice.Colorpicker = Class.create({
  initialize: function(button, callback) {
    var elem = new Element("div").addClassName("color_picker");

    var toggle = new Element("div").addClassName("toggle");
    var blank = new Element("span").addClassName("blank").addClassName("color");
    blank.setStyle({"background-color": "none"});
    blank.insert("&#8416;");
    toggle.insert('<span id="fg" class="active">fg</span><span id="bg">bg</span>');
    toggle.insert(blank);
    elem.insert(toggle);

    var colorcontainer = new Element("div").addClassName("colors");
    this.colors().each(function(color) {
      var box = new Element("span").addClassName("color");
      box.setStyle({"background-color": color});
      colorcontainer.insert(box); 
    });
    elem.insert(colorcontainer);

    button.up('.window').insert(elem);
    elem.observe("mousedown", this.clicked.bind(this));

    this.elem = elem;
    this.cb = callback;
    this.fg = true;
  },

  clicked: function(e) {
    e.stop();

    var box = e.findElement("span.color");
    if (box) {
      var color = box.getStyle("background-color");
      if (color) this.cb(color, this.fg);
      return;
    }

    if (e.findElement("span#fg")) {
      this.elem.down("#bg").removeClassName("active");
      this.elem.down("#fg").addClassName("active");
      this.fg = true;
      return;
    }

    if (e.findElement("span#bg")) {
      this.elem.down("#fg").removeClassName("active");
      this.elem.down("#bg").addClassName("active");
      this.fg = false;
      return;
    }
  },

  remove: function() {
    this.elem.remove();
  },

  colors: function() {
    return ["#fff", "#000", "#008", "#080", "#f00", "#800", "#808", "#f80",
            "#ff0", "#0f0", "#088", "#0ff", "#00f", "#f0f", "#888", "#ccc"];
  }
});
