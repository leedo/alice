Alice.Completion = Class.create({
  initialize: function(input, candidates) {
    this.input = input;
    this.element = this.input.editor;
    this.value = this.input.getValue();
    
    var range = window.getSelection().getRangeAt(0);
    this.index = range.startOffset;
    this.findStem();
    this.matches = this.matchAgainst(candidates);
    this.matchIndex = -1;
  },
  
  next: function() {
    if (!this.matches.length) return;
    if (++this.matchIndex == this.matches.length) this.matchIndex = 0;

    var match = this.matches[this.matchIndex];
    match += this.leftOffset == 0 ? ": " : " ";
    this.restore(match, this.leftOffset + match.length);
  },
  
  restore: function(stem, index) {
    this.input.setValue(this.stemLeft + (stem || this.stem) + this.stemRight);
    this.setCursorToIndex(Object.isUndefined(index) ? this.index : index);
  },
  
  setCursorToIndex: function(index) {
    var selection = window.getSelection();
    if (selection.rangeCount > 0) {
      var range = selection.getRangeAt(0);
      var container = range.startContainer;
      range.setStart(container, index);
      range.setEnd(container, index);
      selection.removeAllRanges();
      selection.addRange(range);
    }
  },

  findStem: function() {
    var left = [], right = [], chr, index, length = this.value.length;

    for (index = this.index - 1; index >= 0; index--) {
      chr = this.value.charAt(index);
      if (!Alice.Completion.PATTERN.test(chr)) break;
      left.unshift(chr);
    }

    for (index = this.index; index < length; index++) {
      chr = this.value.charAt(index);
      if (!Alice.Completion.PATTERN.test(chr)) break;
      right.push(chr);
    }

    this.stem = left.concat(right).join("");
    this.stemLeft  = this.value.substr(0, this.index - left.length);
    this.stemRight = this.value.substr(this.index + right.length);
    this.leftOffset = this.index - left.length;
  },
  
  matchAgainst: function(candidates) {
    return candidates.grep(new RegExp("^" + RegExp.escape(this.stem), "i")).sortBy(function(candidate) {
      return candidate.toLowerCase();
    });
  }
});

Alice.Completion.PATTERN = /[A-Za-z0-9\[\\\]^_{|}-]/;
