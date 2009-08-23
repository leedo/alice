//= require <prototype>
//= require <effects>
//= require <dragdrop>
//= require <shortcut>

var Alice = { };

//= require <alice/util>
//= require <alice/application>
//= require <alice/connection>
//= require <alice/window>
//= require <alice/input>
//= require <alice/keyboard>
//= require <alice/completion>

if (window == window.parent) {
  var alice = new Alice.Application();

  document.observe("dom:loaded", function () {
    $$("tr.topic td").each(function (topic){
      topic.innerHTML = Alice.makeLinksClickable(topic.innerHTML)});
    $('config_button').observe("click", alice.toggleConfig.bind(alice));
    var width = document.viewport.getWidth();
    $$('.messages').invoke('setStyle', {width: width+"px"});
    if (alice.activeWindow()) alice.activeWindow().input.focus()

    setTimeout(function () {
      if (!alice.windows()) alice.toggleConfig.bind(alice), 2000});

    window.onkeydown = function (e) {
      if (alice.activeWindow() && !$('config') && !Alice.isSpecialKey(e.which))
        alice.activeWindow().input.focus()};

    window.onresize = function () {
      if (alice.activeWindow()) alice.activeWindow().scrollToBottom()
      var width = document.viewport.getWidth();
      $$('.messages').invoke('setStyle', {width: width+"px"});
    };

    window.status = " ";  

    window.onfocus = function () {
      if (alice.activeWindow()) alice.activeWindow().input.focus();
      alice.isFocused = true};

    window.onblur = function () {alice.isFocused = false};

    Alice.makeSortable();

    if (Prototype.Browser.MobileSafari) {
      setTimeout(function(){window.scrollTo(0,1)}, 5000);
      $$('button').invoke('setStyle',
        {display:'block',position:'absolute',right:'0px'});
    }
  });
}
