Alice.Autocompleter = Class.create(Ajax.Autocompleter, {
  onKeyPress: function (event) {
    if(this.active)
      switch(event.keyCode) {
        case Event.KEY_TAB:
          this.markNext();
          this.render();
          Event.stop(event);
          alice.activeChannel().scrollToBottom(true);
          return;
        case Event.KEY_RETURN:
          this.selectEntry();
          Event.stop(event);
        case Event.KEY_ESC:
          this.hide();
          this.active = false;
          Event.stop(event);
          return;
        case Event.KEY_LEFT:
          this.markPrevious();
          this.render();
          Event.stop(event);
          return;
        case Event.KEY_RIGHT:
          this.markNext();
          this.render();
          Event.stop(event);
          return;
        case Event.KEY_UP:
          Event.stop(event);
          return;
        case Event.KEY_DOWN:
          Event.stop(event);
          return;
      }
    else if (event.keyCode==Event.KEY_TAB) {
      this.active = true;
      this.show();
      Event.stop(event);
    }
    else
      if(event.keyCode==Event.KEY_RETURN ||
        (Prototype.Browser.WebKit > 0 && event.keyCode == 0)) return;
 
    this.changed = true;
    this.hasFocus = true;
 
    if(this.observer) clearTimeout(this.observer);
    this.observer =
      setTimeout(this.onObserverEvent.bind(this), this.options.frequency*1000);
  },
  render: function() {
    if(this.entryCount > 0) {
      for (var i = 0; i < this.entryCount; i++)
        this.index==i ?
          Element.addClassName(this.getEntry(i),"selected") :
          Element.removeClassName(this.getEntry(i),"selected");
      if(this.hasFocus) {
      // this is triggered by TAB in onKeyPress
      //this.show();
      //this.active = true;
      }
    } else {
      this.active = false;
      this.hide();
    }
  }
});
