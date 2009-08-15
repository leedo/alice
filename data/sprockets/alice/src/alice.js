//= require <prototype>
//= require <effects>
//= require <dragdrop>

var Alice = { };

//= require <alice/application>
//= require <alice/window>
//= require <alice/connection>
//= require <alice/util>

var alice = new Alice.Application();

document.observe("dom:loaded", function () {
  $$("div.topic").each(function (topic){
    topic.innerHTML = alice.linkFilter(topic.innerHTML)});
  $('config_button').observe("click", alice.toggleConfig.bind(alice));
  alice.activeWindow().input.focus()
  window.onkeydown = function () {
    if (! $('config') && ! alice.isCtrl && ! alice.isCommand && ! alice.isAlt)
      alice.activeWindow().input.focus()};
  window.onresize = function () {
    alice.activeWindow().scrollToBottom()};
  window.status = " ";  
  window.onfocus = function () {
    alice.activeWindow().input.focus();
    alice.isFocused = true};
  window.onblur = function () {alice.isFocused = false};
  Alice.makeSortable();
});
