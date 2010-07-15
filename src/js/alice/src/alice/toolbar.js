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
      handler(this.editor);
      this.editor.fire("selection:change");
      event.stop();
    }.bind(this));
  }
});

Alice.Toolbar.ButtonSet = WysiHat.Toolbar.ButtonSets.Basic.concat(
  [
    {
      label: "Colors",
      handler: function (editor) {
      }
    }
  ]
);
