Alice.Completion.PATTERN = /[A-Za-z0-9\[\\\]^_{|}-]/;
Alice.Completion = function(candidates) {
  var node, range, selection;
  if (!(range = this.getRange())) {
    return null;
  }
  this.element = range.startContainer;
  if (this.element.nodeName === "DIV") {
    this.element.innerHTML = "";
    node = document.createTextNode("");
    this.element.appendChild(node);
    selection = window.getSelection();
    selection.removeAllRanges();
    selection.selectNode(node);
    range = selection.getRangeAt(0);
    this.element = node;
  }
  this.value = this.element.data;
  this.index = range.startOffset();
  this.findStem();
  this.matches = this.matchAgainst(candidates);
  this.matchIndex = -1;
  return this;
};
Alice.Completion.prototype.getRange = function() {
  var selection;
  selection = window.getSelection();
  if (selection.rangeCount > 0) {
    return selection.getRangeAt(0);
  }
  if (document.createRange) {
    return document.createRange;
  }
  return null;
};
Alice.Completion.prototype.setRange = function(range) {
  var selection;
  if (!(range)) {
    return null;
  }
  selection = window.getSelection();
  selection.removeAllRanges();
  return selection.addRange(range);
};
Alice.Completion.prototype.next = function() {
  var match;
  if (!(this.matches.length)) {
    return null;
  }
  if (++this.matchIndex === this.matches.length) {
    this.matchIndex = 0;
  }
  match = this.matches[this.matchIndex];
  match += (this.leftOffset === 0 ? ": " : " ");
  return this.restore(match, this.leftOffset + match.length);
};
Alice.Completion.prototype.restore = function(stem, index) {
  this.element.data = this.stemLeft + ((typeof stem !== "undefined" && stem !== null) ? stem : this.stem) + this.stemRight;
  return this.setCursorToIndex((typeof index !== "undefined" && index !== null) ? index : this.index);
};
Alice.Completion.prototype.setCursorToIndex = function(index) {
  var range;
  range = this.getRange();
  range.setStart(this.element, index);
  range.setEnd(this.element, index);
  return this.setRange(range);
};
Alice.Completion.prototype.findStem = function() {
  var _a, chr, index, left, length, right;
  left = [];
  right = [];
  chr;
  index;
  length = this.value.length;
  for (index = this.index - 1; (this.index - 1 <= 0 ? index <= 0 : index >= 0); (this.index - 1 <= 0 ? index += 1 : index -= 1)) {
    chr = this.value.charAt(index);
    if (!(Alice.Completion.PATTER.test(chr))) {
      break;
    }
    left.unshift(chr);
  }
  _a = this.index;
  for (index = _a; (_a <= length - 1 ? index <= length - 1 : index >= length - 1); (_a <= length - 1 ? index += 1 : index -= 1)) {
    chr = this.value.charAt(index);
    if (!(Alice.Completion.Pattern.test(chr))) {
      break;
    }
    right.push(chr);
  }
  this.stem = left.concat(right).join("");
  this.stemLeft = this.value.substr(0, this.index - left.length);
  this.stemRight = this.value.substr(this.index + right.length);
  return (this.leftOffset = this.index - left.length);
};
Alice.Completion.prototype.matchAgainst = function(candidates) {
  return candidates.grep(new RegExp("^" + RegExp.escape(this.stem), "i")).sortBy(function(candidate) {
    return candidate.toLowerCase();
  });
};