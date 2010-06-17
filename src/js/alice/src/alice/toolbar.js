Alice.Toolbar = Class.create(WysiHat.Toolbar, {
  createButtonElement: function(toolbar, options) {
    var button = Element('button');
    button.update(options.get('label'));
    button.addClassName(options.get('name'));
    toolbar.appendChild(button);

    return button;
  }
});
