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
      handler(this.editor, element, this);
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
        var cb = editor.colorSelection.bind(editor);
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
        toolbar.picker.remove();
        toolbar.picker = undefined;
      }
    }
  ]
);

Alice.Colorpicker = Class.create({
  initialize: function(button, callback) {
    var elem = new Element("div").addClassName("color_picker");

    this.colors().each(function(color) {
      var box = new Element("span");
      box.setStyle({"background-color": color});
      elem.insert(box); 
    });

    $('container').insert(elem);
    elem.observe("mousedown", this.clicked.bind(this));

    this.elem = elem;
    this.cb = callback;
  },

  clicked: function(e) {
    e.stop();
    var box = e.findElement("span");
    if (box) {
      var color = box.getStyle("background-color");
      if (color) this.cb(color);
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
