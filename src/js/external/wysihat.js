/*  WysiHat - WYSIWYG JavaScript framework, version 0.2.1
 *  (c) 2008-2010 Joshua Peek
 *
 *  WysiHat is freely distributable under the terms of an MIT-style license.
 *--------------------------------------------------------------------------*/


var WysiHat = {};
WysiHat.Editor = {
  attach: function(textarea) {
    var editArea;

    textarea = $(textarea);

    var id = textarea.id + '_editor';
    if (editArea = $(id)) return editArea;

    editArea = new Element('div', {
      'id': id,
      'class': 'editor',
      'contentEditable': 'true'
    });

    editArea.update(WysiHat.Formatting.getBrowserMarkupFrom(textarea.value));

    Object.extend(editArea, WysiHat.Commands);

    textarea.insert({before: editArea});
    textarea.hide();


    return editArea;
  }
};
WysiHat.BrowserFeatures = (function() {
  function createTmpIframe(callback) {
    var frame, frameDocument;

    frame = new Element('iframe');
    frame.setStyle({
      position: 'absolute',
      left: '-1000px'
    });

    frame.onFrameLoaded(function() {
      if (typeof frame.contentDocument !== 'undefined') {
        frameDocument = frame.contentDocument;
      } else if (typeof frame.contentWindow !== 'undefined' && typeof frame.contentWindow.document !== 'undefined') {
        frameDocument = frame.contentWindow.document;
      }

      frameDocument.designMode = 'on';

      callback(frameDocument);

      frame.remove();
    });

    $(document.body).insert(frame);
  }

  var features = {};

  function detectParagraphType(document) {
    document.body.innerHTML = '';
    document.execCommand('insertparagraph', false, null);

    var tagName;
    element = document.body.childNodes[0];
    if (element && element.tagName)
      tagName = element.tagName.toLowerCase();

    if (tagName == 'div')
      features.paragraphType = "div";
    else if (document.body.innerHTML == "<p><br></p>")
      features.paragraphType = "br";
    else
      features.paragraphType = "p";
  }

  function detectIndentType(document) {
    document.body.innerHTML = 'tab';
    document.execCommand('indent', false, null);

    var tagName;
    element = document.body.childNodes[0];
    if (element && element.tagName)
      tagName = element.tagName.toLowerCase();
    features.indentInsertsBlockquote = (tagName == 'blockquote');
  }

  features.run = function run() {
    if (features.finished) return;

    createTmpIframe(function(document) {
      detectParagraphType(document);
      detectIndentType(document);

      features.finished = true;
    });
  }

  return features;
})();
/*  IE Selection and Range classes
 *
 *  Original created by Tim Cameron Ryan
 *    http://github.com/timcameronryan/IERange
 *  Copyright (c) 2009 Tim Cameron Ryan
 *  Released under the MIT/X License
 *
 *  Modified by Joshua Peek
 */
if (!window.getSelection) {
  var DOMUtils = {
    isDataNode: function(node) {
      try {
        return node && node.nodeValue !== null && node.data !== null;
      } catch (e) {
        return false;
      }
    },
    isAncestorOf: function(parent, node) {
      if (!parent) return false;
      return !DOMUtils.isDataNode(parent) &&
          (parent.contains(DOMUtils.isDataNode(node) ? node.parentNode : node) ||
          node.parentNode == parent);
    },
    isAncestorOrSelf: function(root, node) {
      return DOMUtils.isAncestorOf(root, node) || root == node;
    },
    findClosestAncestor: function(root, node) {
      if (DOMUtils.isAncestorOf(root, node))
        while (node && node.parentNode != root)
          node = node.parentNode;
      return node;
    },
    getNodeLength: function(node) {
      return DOMUtils.isDataNode(node) ? node.length : node.childNodes.length;
    },
    splitDataNode: function(node, offset) {
      if (!DOMUtils.isDataNode(node))
        return false;
      var newNode = node.cloneNode(false);
      node.deleteData(offset, node.length);
      newNode.deleteData(0, offset);
      node.parentNode.insertBefore(newNode, node.nextSibling);
    }
  };

  window.Range = (function() {
    function Range(document) {
      this._document = document;

      this.startContainer = this.endContainer = document.body;
      this.endOffset = DOMUtils.getNodeLength(document.body);
    }
    Range.START_TO_START = 0;
    Range.START_TO_END = 1;
    Range.END_TO_END = 2;
    Range.END_TO_START = 3;

    function findChildPosition(node) {
      for (var i = 0; node = node.previousSibling; i++)
        continue;
      return i;
    }

    Range.prototype = {
      startContainer: null,
      startOffset: 0,
      endContainer: null,
      endOffset: 0,
      commonAncestorContainer: null,
      collapsed: false,
      _document: null,

      _toTextRange: function() {
        function adoptEndPoint(textRange, domRange, bStart) {
          var container = domRange[bStart ? 'startContainer' : 'endContainer'];
          var offset = domRange[bStart ? 'startOffset' : 'endOffset'], textOffset = 0;
          var anchorNode = DOMUtils.isDataNode(container) ? container : container.childNodes[offset];
          var anchorParent = DOMUtils.isDataNode(container) ? container.parentNode : container;

          if (container.nodeType == 3 || container.nodeType == 4)
            textOffset = offset;

          var cursorNode = domRange._document.createElement('a');
          if (anchorNode)
            anchorParent.insertBefore(cursorNode, anchorNode);
          else
            anchorParent.appendChild(cursorNode);
          var cursor = domRange._document.body.createTextRange();
          cursor.moveToElementText(cursorNode);
          cursorNode.parentNode.removeChild(cursorNode);

          textRange.setEndPoint(bStart ? 'StartToStart' : 'EndToStart', cursor);
          textRange[bStart ? 'moveStart' : 'moveEnd']('character', textOffset);
        }

        var textRange = this._document.body.createTextRange();
        adoptEndPoint(textRange, this, true);
        adoptEndPoint(textRange, this, false);
        return textRange;
      },

      _refreshProperties: function() {
        this.collapsed = (this.startContainer == this.endContainer && this.startOffset == this.endOffset);
        var node = this.startContainer;
        while (node && node != this.endContainer && !DOMUtils.isAncestorOf(node, this.endContainer))
          node = node.parentNode;
        this.commonAncestorContainer = node;
      },

      setStart: function(container, offset) {
        this.startContainer = container;
        this.startOffset = offset;
        this._refreshProperties();
      },
      setEnd: function(container, offset) {
        this.endContainer = container;
        this.endOffset = offset;
        this._refreshProperties();
      },
      setStartBefore: function(refNode) {
        this.setStart(refNode.parentNode, findChildPosition(refNode));
      },
      setStartAfter: function(refNode) {
        this.setStart(refNode.parentNode, findChildPosition(refNode) + 1);
      },
      setEndBefore: function(refNode) {
        this.setEnd(refNode.parentNode, findChildPosition(refNode));
      },
      setEndAfter: function(refNode) {
        this.setEnd(refNode.parentNode, findChildPosition(refNode) + 1);
      },
      selectNode: function(refNode) {
        this.setStartBefore(refNode);
        this.setEndAfter(refNode);
      },
      selectNodeContents: function(refNode) {
        this.setStart(refNode, 0);
        this.setEnd(refNode, DOMUtils.getNodeLength(refNode));
      },
      collapse: function(toStart) {
        if (toStart)
          this.setEnd(this.startContainer, this.startOffset);
        else
          this.setStart(this.endContainer, this.endOffset);
      },

      cloneContents: function() {
        return (function cloneSubtree(iterator) {
          for (var node, frag = document.createDocumentFragment(); node = iterator.next(); ) {
            node = node.cloneNode(!iterator.hasPartialSubtree());
            if (iterator.hasPartialSubtree())
              node.appendChild(cloneSubtree(iterator.getSubtreeIterator()));
            frag.appendChild(node);
          }
          return frag;
        })(new RangeIterator(this));
      },
      extractContents: function() {
        var range = this.cloneRange();
        if (this.startContainer != this.commonAncestorContainer)
          this.setStartAfter(DOMUtils.findClosestAncestor(this.commonAncestorContainer, this.startContainer));
        this.collapse(true);
        return (function extractSubtree(iterator) {
          for (var node, frag = document.createDocumentFragment(); node = iterator.next(); ) {
            iterator.hasPartialSubtree() ? node = node.cloneNode(false) : iterator.remove();
            if (iterator.hasPartialSubtree())
              node.appendChild(extractSubtree(iterator.getSubtreeIterator()));
            frag.appendChild(node);
          }
          return frag;
        })(new RangeIterator(range));
      },
      deleteContents: function() {
        var range = this.cloneRange();
        if (this.startContainer != this.commonAncestorContainer)
          this.setStartAfter(DOMUtils.findClosestAncestor(this.commonAncestorContainer, this.startContainer));
        this.collapse(true);
        (function deleteSubtree(iterator) {
          while (iterator.next())
            iterator.hasPartialSubtree() ? deleteSubtree(iterator.getSubtreeIterator()) : iterator.remove();
        })(new RangeIterator(range));
      },
      insertNode: function(newNode) {
        if (DOMUtils.isDataNode(this.startContainer)) {
          DOMUtils.splitDataNode(this.startContainer, this.startOffset);
          this.startContainer.parentNode.insertBefore(newNode, this.startContainer.nextSibling);
        } else {
          var offsetNode = this.startContainer.childNodes[this.startOffset];
          if (offsetNode) {
            this.startContainer.insertBefore(newNode, offsetNode);
          } else {
            this.startContainer.appendChild(newNode);
          }
        }
        this.setStart(this.startContainer, this.startOffset);
      },
      surroundContents: function(newNode) {
        var content = this.extractContents();
        this.insertNode(newNode);
        newNode.appendChild(content);
        this.selectNode(newNode);
      },

      compareBoundaryPoints: function(how, sourceRange) {
        var containerA, offsetA, containerB, offsetB;
        switch (how) {
            case Range.START_TO_START:
            case Range.START_TO_END:
          containerA = this.startContainer;
          offsetA = this.startOffset;
          break;
            case Range.END_TO_END:
            case Range.END_TO_START:
          containerA = this.endContainer;
          offsetA = this.endOffset;
          break;
        }
        switch (how) {
            case Range.START_TO_START:
            case Range.END_TO_START:
          containerB = sourceRange.startContainer;
          offsetB = sourceRange.startOffset;
          break;
            case Range.START_TO_END:
            case Range.END_TO_END:
          containerB = sourceRange.endContainer;
          offsetB = sourceRange.endOffset;
          break;
        }

        return containerA.sourceIndex < containerB.sourceIndex ? -1 :
            containerA.sourceIndex == containerB.sourceIndex ?
                offsetA < offsetB ? -1 : offsetA == offsetB ? 0 : 1
                : 1;
      },
      cloneRange: function() {
        var range = new Range(this._document);
        range.setStart(this.startContainer, this.startOffset);
        range.setEnd(this.endContainer, this.endOffset);
        return range;
      },
      detach: function() {
      },
      toString: function() {
        return this._toTextRange().text;
      },
      createContextualFragment: function(tagString) {
        var content = (DOMUtils.isDataNode(this.startContainer) ? this.startContainer.parentNode : this.startContainer).cloneNode(false);
        content.innerHTML = tagString;
        for (var fragment = this._document.createDocumentFragment(); content.firstChild; )
          fragment.appendChild(content.firstChild);
        return fragment;
      }
    };

    function RangeIterator(range) {
      this.range = range;
      if (range.collapsed)
        return;

      var root = range.commonAncestorContainer;
      this._next = range.startContainer == root && !DOMUtils.isDataNode(range.startContainer) ?
          range.startContainer.childNodes[range.startOffset] :
          DOMUtils.findClosestAncestor(root, range.startContainer);
      this._end = range.endContainer == root && !DOMUtils.isDataNode(range.endContainer) ?
          range.endContainer.childNodes[range.endOffset] :
          DOMUtils.findClosestAncestor(root, range.endContainer).nextSibling;
    }

    RangeIterator.prototype = {
      range: null,
      _current: null,
      _next: null,
      _end: null,

      hasNext: function() {
        return !!this._next;
      },
      next: function() {
        var current = this._current = this._next;
        this._next = this._current && this._current.nextSibling != this._end ?
            this._current.nextSibling : null;

        if (DOMUtils.isDataNode(this._current)) {
          if (this.range.endContainer == this._current)
            (current = current.cloneNode(true)).deleteData(this.range.endOffset, current.length - this.range.endOffset);
          if (this.range.startContainer == this._current)
            (current = current.cloneNode(true)).deleteData(0, this.range.startOffset);
        }
        return current;
      },
      remove: function() {
        if (DOMUtils.isDataNode(this._current) &&
            (this.range.startContainer == this._current || this.range.endContainer == this._current)) {
          var start = this.range.startContainer == this._current ? this.range.startOffset : 0;
          var end = this.range.endContainer == this._current ? this.range.endOffset : this._current.length;
          this._current.deleteData(start, end - start);
        } else
          this._current.parentNode.removeChild(this._current);
      },
      hasPartialSubtree: function() {
        return !DOMUtils.isDataNode(this._current) &&
            (DOMUtils.isAncestorOrSelf(this._current, this.range.startContainer) ||
                DOMUtils.isAncestorOrSelf(this._current, this.range.endContainer));
      },
      getSubtreeIterator: function() {
        var subRange = new Range(this.range._document);
        subRange.selectNodeContents(this._current);
        if (DOMUtils.isAncestorOrSelf(this._current, this.range.startContainer))
          subRange.setStart(this.range.startContainer, this.range.startOffset);
        if (DOMUtils.isAncestorOrSelf(this._current, this.range.endContainer))
          subRange.setEnd(this.range.endContainer, this.range.endOffset);
        return new RangeIterator(subRange);
      }
    };

    return Range;
  })();

  window.Range._fromTextRange = function(textRange, document) {
    function adoptBoundary(domRange, textRange, bStart) {
      var cursorNode = document.createElement('a'), cursor = textRange.duplicate();
      cursor.collapse(bStart);
      var parent = cursor.parentElement();
      do {
        parent.insertBefore(cursorNode, cursorNode.previousSibling);
        cursor.moveToElementText(cursorNode);
      } while (cursor.compareEndPoints(bStart ? 'StartToStart' : 'StartToEnd', textRange) > 0 && cursorNode.previousSibling);

      if (cursor.compareEndPoints(bStart ? 'StartToStart' : 'StartToEnd', textRange) == -1 && cursorNode.nextSibling) {
        cursor.setEndPoint(bStart ? 'EndToStart' : 'EndToEnd', textRange);
        domRange[bStart ? 'setStart' : 'setEnd'](cursorNode.nextSibling, cursor.text.length);
      } else {
        domRange[bStart ? 'setStartBefore' : 'setEndBefore'](cursorNode);
      }
      cursorNode.parentNode.removeChild(cursorNode);
    }

    var domRange = new Range(document);
    adoptBoundary(domRange, textRange, true);
    adoptBoundary(domRange, textRange, false);
    return domRange;
  }

  document.createRange = function() {
    return new Range(document);
  };

  window.Selection = (function() {
    function Selection(document) {
      this._document = document;

      var selection = this;
      document.attachEvent('onselectionchange', function() {
        selection._selectionChangeHandler();
      });
    }

    Selection.prototype = {
      rangeCount: 0,
      _document: null,

      _selectionChangeHandler: function() {
        this.rangeCount = this._selectionExists(this._document.selection.createRange()) ? 1 : 0;
      },
      _selectionExists: function(textRange) {
        return textRange.compareEndPoints('StartToEnd', textRange) != 0 ||
            textRange.parentElement().isContentEditable;
      },
      addRange: function(range) {
        var selection = this._document.selection.createRange(), textRange = range._toTextRange();
        if (!this._selectionExists(selection)) {
          textRange.select();
        } else {
          if (textRange.compareEndPoints('StartToStart', selection) == -1)
            if (textRange.compareEndPoints('StartToEnd', selection) > -1 &&
                textRange.compareEndPoints('EndToEnd', selection) == -1)
              selection.setEndPoint('StartToStart', textRange);
          else
            if (textRange.compareEndPoints('EndToStart', selection) < 1 &&
                textRange.compareEndPoints('EndToEnd', selection) > -1)
              selection.setEndPoint('EndToEnd', textRange);
          selection.select();
        }
      },
      removeAllRanges: function() {
        this._document.selection.empty();
      },
      getRangeAt: function(index) {
        var textRange = this._document.selection.createRange();
        if (this._selectionExists(textRange))
          return Range._fromTextRange(textRange, this._document);
        return null;
      },
      toString: function() {
        return this._document.selection.createRange().text;
      }
    };

    return Selection;
  })();

  window.getSelection = (function() {
    var selection = new Selection(document);
    return function() { return selection; };
  })();

  window.getSelection.custom = true;
}

Object.extend(Range.prototype, (function() {
  function beforeRange(range) {
    if (!range || !range.compareBoundaryPoints) return false;
    return (this.compareBoundaryPoints(this.START_TO_START, range) == -1 &&
      this.compareBoundaryPoints(this.START_TO_END, range) == -1 &&
      this.compareBoundaryPoints(this.END_TO_END, range) == -1 &&
      this.compareBoundaryPoints(this.END_TO_START, range) == -1);
  }

  function afterRange(range) {
    if (!range || !range.compareBoundaryPoints) return false;
    return (this.compareBoundaryPoints(this.START_TO_START, range) == 1 &&
      this.compareBoundaryPoints(this.START_TO_END, range) == 1 &&
      this.compareBoundaryPoints(this.END_TO_END, range) == 1 &&
      this.compareBoundaryPoints(this.END_TO_START, range) == 1);
  }

  function betweenRange(range) {
    if (!range || !range.compareBoundaryPoints) return false;
    return !(this.beforeRange(range) || this.afterRange(range));
  }

  function equalRange(range) {
    if (!range || !range.compareBoundaryPoints) return false;
    return (this.compareBoundaryPoints(this.START_TO_START, range) == 0 &&
      this.compareBoundaryPoints(this.START_TO_END, range) == 1 &&
      this.compareBoundaryPoints(this.END_TO_END, range) == 0 &&
      this.compareBoundaryPoints(this.END_TO_START, range) == -1);
  }

  function getNode() {
    var parent = this.commonAncestorContainer;

    while (parent.nodeType == Node.TEXT_NODE)
      parent = parent.parentNode;

    var child = parent.childElements().detect(function(child) {
      var range = document.createRange();
      range.selectNodeContents(child);
      return this.betweenRange(range);
    }.bind(this));

    return $(child || parent);
  }

  return {
    beforeRange:  beforeRange,
    afterRange:   afterRange,
    betweenRange: betweenRange,
    equalRange:   equalRange,
    getNode:      getNode
  };
})());

if (window.getSelection.custom) {
  Object.extend(Selection.prototype, (function() {
    function getNode() {
      var range = this._document.selection.createRange();
      return $(range.parentElement());
    }

    function selectNode(element) {
      var range = this._document.body.createTextRange();
      range.moveToElementText(element);
      range.select();
    }

    return {
      getNode:    getNode,
      selectNode: selectNode
    }
  })());
} else {
  if (typeof Selection == 'undefined') {
    var Selection = {}
    Selection.prototype = window.getSelection().__proto__;
  }

  Object.extend(Selection.prototype, (function() {
    function getNode() {
      if (this.rangeCount > 0)
        return this.getRangeAt(0).getNode();
      else
        return null;
    }

    function selectNode(element) {
      var range = document.createRange();
      range.selectNode(element);
      this.removeAllRanges();
      this.addRange(range);
    }

    return {
      getNode:    getNode,
      selectNode: selectNode
    }
  })());
}
document.on("dom:loaded", function() {
  function fieldChangeHandler(event, element) {
    var value;

    if (element.contentEditable == 'true')
      value = element.innerHTML;
    else if (element.getValue)
      value = element.getValue();

    if (value && element.previousValue != value) {
      element.fire("field:change");
      element.previousValue = value;
    }
  }

  $(document.body).on("keyup", 'input,textarea,*[contenteditable=""],*[contenteditable=true]', fieldChangeHandler);
});

WysiHat.Commands = (function(window) {
  function boldSelection() {
    this.execCommand('bold', false, null);
  }

  function boldSelected() {
    return this.queryCommandState('bold');
  }

  function underlineSelection() {
    this.execCommand('underline', false, null);
  }

  function underlineSelected() {
    return this.queryCommandState('underline');
  }

  function italicSelection() {
    this.execCommand('italic', false, null);
  }

  function italicSelected() {
    return this.queryCommandState('italic');
  }

  function strikethroughSelection() {
    this.execCommand('strikethrough', false, null);
  }

  function indentSelection() {
    if (Prototype.Browser.Gecko) {
      var selection, range, node, blockquote;

      selection = window.getSelection();
      range     = selection.getRangeAt(0);
      node      = selection.getNode();

      if (range.collapsed) {
        range = document.createRange();
        range.selectNodeContents(node);
        selection.removeAllRanges();
        selection.addRange(range);
      }

      blockquote = new Element('blockquote');
      range = selection.getRangeAt(0);
      range.surroundContents(blockquote);
    } else {
      this.execCommand('indent', false, null);
    }
  }

  function outdentSelection() {
    this.execCommand('outdent', false, null);
  }

  function toggleIndentation() {
    if (this.indentSelected()) {
      this.outdentSelection();
    } else {
      this.indentSelection();
    }
  }

  function indentSelected() {
    var node = window.getSelection().getNode();
    return node.match("blockquote, blockquote *");
  }

  function fontSelection(font) {
    this.execCommand('fontname', false, font);
  }

  function fontSizeSelection(fontSize) {
    this.execCommand('fontsize', false, fontSize);
  }

  function colorSelection(color) {
    this.execCommand('forecolor', false, color);
  }

  function backgroundColorSelection(color) {
    if(Prototype.Browser.Gecko) {
      this.execCommand('hilitecolor', false, color);
    } else {
      this.execCommand('backcolor', false, color);
    }
  }

  function alignSelection(alignment) {
    this.execCommand('justify' + alignment);
  }

  function alignSelected() {
    var node = window.getSelection().getNode();
    return Element.getStyle(node, 'textAlign');
  }

  function linkSelection(url) {
    this.execCommand('createLink', false, url);
  }

  function unlinkSelection() {
    var node = window.getSelection().getNode();
    if (this.linkSelected())
      window.getSelection().selectNode(node);

    this.execCommand('unlink', false, null);
  }

  function linkSelected() {
    var node = window.getSelection().getNode();
    return node ? node.tagName.toUpperCase() == 'A' : false;
  }

  function formatblockSelection(element){
    this.execCommand('formatblock', false, element);
  }

  function toggleOrderedList() {
    var selection, node;

    selection = window.getSelection();
    node      = selection.getNode();

    if (this.orderedListSelected() && !node.match("ol li:last-child, ol li:last-child *")) {
      selection.selectNode(node.up("ol"));
    } else if (this.unorderedListSelected()) {
      selection.selectNode(node.up("ul"));
    }

    this.execCommand('insertorderedlist', false, null);
  }

  function insertOrderedList() {
    this.toggleOrderedList();
  }

  function orderedListSelected() {
    var element = window.getSelection().getNode();
    if (element) return element.match('*[contenteditable=""] ol, *[contenteditable=true] ol, *[contenteditable=""] ol *, *[contenteditable=true] ol *');
    return false;
  }

  function toggleUnorderedList() {
    var selection, node;

    selection = window.getSelection();
    node      = selection.getNode();

    if (this.unorderedListSelected() && !node.match("ul li:last-child, ul li:last-child *")) {
      selection.selectNode(node.up("ul"));
    } else if (this.orderedListSelected()) {
      selection.selectNode(node.up("ol"));
    }

    this.execCommand('insertunorderedlist', false, null);
  }

  function insertUnorderedList() {
    this.toggleUnorderedList();
  }

  function unorderedListSelected() {
    var element = window.getSelection().getNode();
    if (element) return element.match('*[contenteditable=""] ul, *[contenteditable=true] ul, *[contenteditable=""] ul *, *[contenteditable=true] ul *');
    return false;
  }

  function insertImage(url) {
    this.execCommand('insertImage', false, url);
  }

  function insertHTML(html) {
    if (Prototype.Browser.IE) {
      var range = window.document.selection.createRange();
      range.pasteHTML(html);
      range.collapse(false);
      range.select();
    } else {
      this.execCommand('insertHTML', false, html);
    }
  }

  function execCommand(command, ui, value) {
    var handler = this.commands.get(command);
    if (handler) {
      handler.bind(this)(value);
    } else {
      try {
        window.document.execCommand(command, ui, value);
      } catch(e) { return null; }
    }

    document.activeElement.fire("field:change");
  }

  function queryCommandState(state) {
    var handler = this.queryCommands.get(state);
    if (handler) {
      return handler.bind(this)();
    } else {
      try {
        return window.document.queryCommandState(state);
      } catch(e) { return null; }
    }
  }

  function getSelectedStyles() {
    var styles = $H({});
    var editor = this;
    editor.styleSelectors.each(function(style){
      var node = editor.selection.getNode();
      styles.set(style.first(), Element.getStyle(node, style.last()));
    });
    return styles;
  }

  return {
     boldSelection:            boldSelection,
     boldSelected:             boldSelected,
     underlineSelection:       underlineSelection,
     underlineSelected:        underlineSelected,
     italicSelection:          italicSelection,
     italicSelected:           italicSelected,
     strikethroughSelection:   strikethroughSelection,
     indentSelection:          indentSelection,
     outdentSelection:         outdentSelection,
     toggleIndentation:        toggleIndentation,
     indentSelected:           indentSelected,
     fontSelection:            fontSelection,
     fontSizeSelection:        fontSizeSelection,
     colorSelection:           colorSelection,
     backgroundColorSelection: backgroundColorSelection,
     alignSelection:           alignSelection,
     alignSelected:            alignSelected,
     linkSelection:            linkSelection,
     unlinkSelection:          unlinkSelection,
     linkSelected:             linkSelected,
     formatblockSelection:     formatblockSelection,
     toggleOrderedList:        toggleOrderedList,
     insertOrderedList:        insertOrderedList,
     orderedListSelected:      orderedListSelected,
     toggleUnorderedList:      toggleUnorderedList,
     insertUnorderedList:      insertUnorderedList,
     unorderedListSelected:    unorderedListSelected,
     insertImage:              insertImage,
     insertHTML:               insertHTML,
     execCommand:              execCommand,
     queryCommandState:        queryCommandState,
     getSelectedStyles:        getSelectedStyles,

    commands: $H({}),

    queryCommands: $H({
      link:          linkSelected,
      orderedlist:   orderedListSelected,
      unorderedlist: unorderedListSelected
    }),

    styleSelectors: $H({
      fontname:    'fontFamily',
      fontsize:    'fontSize',
      forecolor:   'color',
      hilitecolor: 'backgroundColor',
      backcolor:   'backgroundColor'
    })
  };
})(window);

if (Prototype.Browser.IE) {
  Object.extend(Selection.prototype, (function() {
    function setBookmark() {
      var bookmark = $('bookmark');
      if (bookmark) bookmark.remove();

      bookmark = new Element('span', { 'id': 'bookmark' }).update("&nbsp;");
      var parent = new Element('div');
      parent.appendChild(bookmark);

      var range = this._document.selection.createRange();
      range.collapse();
      range.pasteHTML(parent.innerHTML);
    }

    function moveToBookmark() {
      var bookmark = $('bookmark');
      if (!bookmark) return;

      var range = this._document.selection.createRange();
      range.moveToElementText(bookmark);
      range.collapse();
      range.select();

      bookmark.remove();
    }

    return {
      setBookmark:    setBookmark,
      moveToBookmark: moveToBookmark
    }
  })());
} else {
  Object.extend(Selection.prototype, (function() {
    function setBookmark() {
      var bookmark = $('bookmark');
      if (bookmark) bookmark.remove();

      bookmark = new Element('span', { 'id': 'bookmark' }).update("&nbsp;");
      this.getRangeAt(0).insertNode(bookmark);
    }

    function moveToBookmark() {
      var bookmark = $('bookmark');
      if (!bookmark) return;

      var range = document.createRange();
      range.setStartBefore(bookmark);
      this.removeAllRanges();
      this.addRange(range);

      bookmark.remove();
    }

    return {
      setBookmark:    setBookmark,
      moveToBookmark: moveToBookmark
    }
  })());
}
(function() {
  function cloneWithAllowedAttributes(element, allowedAttributes) {
    var result = new Element(element.tagName), length = allowedAttributes.length, i;
    element = $(element);

    for (i = 0; i < allowedAttributes.length; i++) {
      attribute = allowedAttributes[i];
      if (element.hasAttribute(attribute)) {
        result.writeAttribute(attribute, element.readAttribute(attribute));
      }
    }

    return result;
  }

  function withEachChildNodeOf(element, callback) {
    var nodes = $A(element.childNodes), length = nodes.length, i;
    for (i = 0; i < length; i++) callback(nodes[i]);
  }

  function sanitizeNode(node, tagsToRemove, tagsToAllow, tagsToSkip) {
    var parentNode = node.parentNode;

    switch (node.nodeType) {
      case Node.ELEMENT_NODE:
        var tagName = node.tagName.toLowerCase();

        if (tagsToSkip) {
          var newNode = node.cloneNode(false);
          withEachChildNodeOf(node, function(childNode) {
            newNode.appendChild(childNode);
            sanitizeNode(childNode, tagsToRemove, tagsToAllow, tagsToSkip);
          });
          parentNode.insertBefore(newNode, node);

        } else if (tagName in tagsToAllow) {
          var newNode = cloneWithAllowedAttributes(node, tagsToAllow[tagName]);
          withEachChildNodeOf(node, function(childNode) {
            newNode.appendChild(childNode);
            sanitizeNode(childNode, tagsToRemove, tagsToAllow, tagsToSkip);
          });
          parentNode.insertBefore(newNode, node);

        } else if (!(tagName in tagsToRemove)) {
          withEachChildNodeOf(node, function(childNode) {
            parentNode.insertBefore(childNode, node);
            sanitizeNode(childNode, tagsToRemove, tagsToAllow, tagsToSkip);
          });
        }

      case Node.COMMENT_NODE:
        parentNode.removeChild(node);
    }
  }

  Element.addMethods({
    sanitizeContents: function(element, options) {
      element = $(element);

      var tagsToRemove = {};
      (options.remove || "").split(",").each(function(tagName) {
        tagsToRemove[tagName.strip()] = true;
      });

      var tagsToAllow = {};
      (options.allow || "").split(",").each(function(selector) {
        var parts = selector.strip().split(/[\[\]]/);
        var tagName = parts[0], allowedAttributes = parts.slice(1).grep(/./);
        tagsToAllow[tagName] = allowedAttributes;
      });

      var tagsToSkip = options.skip;

      withEachChildNodeOf(element, function(childNode) {
        sanitizeNode(childNode, tagsToRemove, tagsToAllow, tagsToSkip);
      });

      return element;
    }
  });
})();
(function() {
  function onReadyStateComplete(document, callback) {
    var handler;

    function checkReadyState() {
      if (document.readyState === 'complete') {
        if (handler) handler.stop();
        callback();
        return true;
      } else {
        return false;
      }
    }

    handler = Element.on(document, 'readystatechange', checkReadyState);
    checkReadyState();
  }

  function observeFrameContentLoaded(element) {
    element = $(element);

    var loaded, contentLoadedHandler;

    loaded = false;
    function fireFrameLoaded() {
      if (loaded) return;

      loaded = true;
      if (contentLoadedHandler) contentLoadedHandler.stop();
      element.fire('frame:loaded');
    }

    if (window.addEventListener) {
      contentLoadedHandler = document.on("DOMFrameContentLoaded", function(event) {
        if (element == event.element())
          fireFrameLoaded();
      });
    }

    element.on('load', function() {
      var frameDocument;

      if (typeof element.contentDocument !== 'undefined') {
        frameDocument = element.contentDocument;
      } else if (typeof element.contentWindow !== 'undefined' && typeof element.contentWindow.document !== 'undefined') {
        frameDocument = element.contentWindow.document;
      }

      onReadyStateComplete(frameDocument, fireFrameLoaded);
    });

    return element;
  }

  function onFrameLoaded(element, callback) {
    element.on('frame:loaded', callback);
    element.observeFrameContentLoaded();
  }

  Element.addMethods({
    observeFrameContentLoaded: observeFrameContentLoaded,
    onFrameLoaded: onFrameLoaded
  });
})();
document.on("dom:loaded", function() {
  if ('selection' in document && 'onselectionchange' in document) {
    var selectionChangeHandler = function() {
      var range   = document.selection.createRange();
      var element = range.parentElement();
      $(element).fire("selection:change");
    }

    document.on("selectionchange", selectionChangeHandler);
  } else {
    var previousRange;

    var selectionChangeHandler = function() {
      var element        = document.activeElement;
      var elementTagName = element.tagName.toLowerCase();

      if (elementTagName == "textarea" || elementTagName == "input") {
        previousRange = null;
        $(element).fire("selection:change");
      } else {
        var selection = window.getSelection();
        if (selection.rangeCount < 1) return;

        var range = selection.getRangeAt(0);
        if (range && range.equalRange(previousRange)) return;
        previousRange = range;

        element = range.commonAncestorContainer;
        while (element.nodeType == Node.TEXT_NODE)
          element = element.parentNode;

        $(element).fire("selection:change");
      }
    };

    document.on("mouseup", selectionChangeHandler);
    document.on("keyup", selectionChangeHandler);
  }
});
WysiHat.Formatting = (function() {
  var ACCUMULATING_LINE      = {};
  var EXPECTING_LIST_ITEM    = {};
  var ACCUMULATING_LIST_ITEM = {};

  return {
    getBrowserMarkupFrom: function(applicationMarkup) {
      var container = new Element("div").update(applicationMarkup);

      function spanify(element, style) {
        element.replace(
          '<span style="' + style +
          '" class="Apple-style-span">' +
          element.innerHTML + '</span>'
        );
      }

      function convertStrongsToSpans() {
        container.select("strong").each(function(element) {
          spanify(element, "font-weight: bold");
        });
      }

      function convertEmsToSpans() {
        container.select("em").each(function(element) {
          spanify(element, "font-style: italic");
        });
      }

      function convertDivsToParagraphs() {
        container.select("div").each(function(element) {
          element.replace("<p>" + element.innerHTML + "</p>");
        });
      }

      if (Prototype.Browser.WebKit || Prototype.Browser.Gecko) {
        convertStrongsToSpans();
        convertEmsToSpans();
      } else if (Prototype.Browser.IE || Prototype.Browser.Opera) {
        convertDivsToParagraphs();
      }

      return container.innerHTML;
    },

    getApplicationMarkupFrom: function(element) {
      var mode = ACCUMULATING_LINE, result, container, line, lineContainer, previousAccumulation;

      function walk(nodes) {
        var length = nodes.length, node, tagName, i;

        for (i = 0; i < length; i++) {
          node = nodes[i];

          if (node.nodeType == Node.ELEMENT_NODE) {
            tagName = node.tagName.toLowerCase();
            open(tagName, node);
            walk(node.childNodes);
            close(tagName);

          } else if (node.nodeType == Node.TEXT_NODE) {
            read(node.nodeValue);
          }
        }
      }

      function open(tagName, node) {
        if (mode == ACCUMULATING_LINE) {
          if (isBlockElement(tagName)) {
            if (isEmptyParagraph(node)) {
              accumulate(new Element("br"));
            }

            flush();

            if (isListElement(tagName)) {
              container = insertList(tagName);
              mode = EXPECTING_LIST_ITEM;
            }

          } else if (isLineBreak(tagName)) {
            if (isLineBreak(getPreviouslyAccumulatedTagName())) {
              previousAccumulation.parentNode.removeChild(previousAccumulation);
              flush();
            }

            accumulate(node.cloneNode(false));

            if (!previousAccumulation.previousNode) flush();

          } else {
            accumulateInlineElement(tagName, node);
          }

        } else if (mode == EXPECTING_LIST_ITEM) {
          if (isListItemElement(tagName)) {
            mode = ACCUMULATING_LIST_ITEM;
          }

        } else if (mode == ACCUMULATING_LIST_ITEM) {
          if (isLineBreak(tagName)) {
            accumulate(node.cloneNode(false));

          } else if (!isBlockElement(tagName)) {
            accumulateInlineElement(tagName, node);
          }
        }
      }

      function close(tagName) {
        if (mode == ACCUMULATING_LINE) {
          if (isLineElement(tagName)) {
            flush();
          }

          if (line != lineContainer) {
            lineContainer = lineContainer.parentNode;
          }

        } else if (mode == EXPECTING_LIST_ITEM) {
          if (isListElement(tagName)) {
            container = result;
            mode = ACCUMULATING_LINE;
          }

        } else if (mode == ACCUMULATING_LIST_ITEM) {
          if (isListItemElement(tagName)) {
            flush();
            mode = EXPECTING_LIST_ITEM;
          }

          if (line != lineContainer) {
            lineContainer = lineContainer.parentNode;
          }
        }
      }

      function isBlockElement(tagName) {
        return isLineElement(tagName) || isListElement(tagName);
      }

      function isLineElement(tagName) {
        return tagName == "p" || tagName == "div";
      }

      function isListElement(tagName) {
        return tagName == "ol" || tagName == "ul";
      }

      function isListItemElement(tagName) {
        return tagName == "li";
      }

      function isLineBreak(tagName) {
        return tagName == "br";
      }

      function isEmptyParagraph(node) {
        return node.tagName.toLowerCase() == "p" && node.childNodes.length == 0;
      }

      function read(value) {
        accumulate(document.createTextNode(value));
      }

      function accumulateInlineElement(tagName, node) {
        var element = node.cloneNode(false);

        if (tagName == "span") {
          if ($(node).getStyle("fontWeight") == "bold") {
            element = new Element("strong");

          } else if ($(node).getStyle("fontStyle") == "italic") {
            element = new Element("em");
          }
        }

        accumulate(element);
        lineContainer = element;
      }

      function accumulate(node) {
        if (mode != EXPECTING_LIST_ITEM) {
          if (!line) line = lineContainer = createLine();
          previousAccumulation = node;
          lineContainer.appendChild(node);
        }
      }

      function getPreviouslyAccumulatedTagName() {
        if (previousAccumulation && previousAccumulation.nodeType == Node.ELEMENT_NODE) {
          return previousAccumulation.tagName.toLowerCase();
        }
      }

      function flush() {
        if (line && line.childNodes.length) {
          container.appendChild(line);
          line = lineContainer = null;
        }
      }

      function createLine() {
        if (mode == ACCUMULATING_LINE) {
          return new Element("div");
        } else if (mode == ACCUMULATING_LIST_ITEM) {
          return new Element("li");
        }
      }

      function insertList(tagName) {
        var list = new Element(tagName);
        result.appendChild(list);
        return list;
      }

      result = container = new Element("div");
      walk(element.childNodes);
      flush();
      return result.innerHTML;
    }
  };
})();

WysiHat.Toolbar = Class.create((function() {
  function initialize(editor) {
    this.editor = editor;
    this.element = this.createToolbarElement();
  }

  function createToolbarElement() {
    var toolbar = new Element('div', { 'class': 'editor_toolbar' });
    this.editor.insert({before: toolbar});
    return toolbar;
  }

  function addButtonSet(set) {
    $A(set).each(function(button){
      this.addButton(button);
    }.bind(this));
  }

  function addButton(options, handler) {
    options = $H(options);

    if (!options.get('name'))
      options.set('name', options.get('label').toLowerCase());
    var name = options.get('name');

    var button = this.createButtonElement(this.element, options);

    var handler = this.buttonHandler(name, options);
    this.observeButtonClick(button, handler);

    var handler = this.buttonStateHandler(name, options);
    this.observeStateChanges(button, name, handler);
  }

  function createButtonElement(toolbar, options) {
    var button = new Element('a', {
      'class': 'button', 'href': '#'
    });
    button.update('<span>' + options.get('label') + '</span>');
    button.addClassName(options.get('name'));

    toolbar.appendChild(button);

    return button;
  }

  function buttonHandler(name, options) {
    if (options.handler)
      return options.handler;
    else if (options.get('handler'))
      return options.get('handler');
    else
      return function(editor) { editor.execCommand(name); };
  }

  function observeButtonClick(element, handler) {
    element.on('click', function(event) {
      handler(this.editor);
      event.stop();
    }.bind(this));
  }

  function buttonStateHandler(name, options) {
    if (options.query)
      return options.query;
    else if (options.get('query'))
      return options.get('query');
    else
      return function(editor) { return editor.queryCommandState(name); };
  }

  function observeStateChanges(element, name, handler) {
    var previousState;
    this.editor.on("selection:change", function(event) {
      var state = handler(this.editor);
      if (state != previousState) {
        previousState = state;
        this.updateButtonState(element, name, state);
      }
    }.bind(this));
  }

  function updateButtonState(element, name, state) {
    if (state)
      element.addClassName('selected');
    else
      element.removeClassName('selected');
  }

  return {
    initialize:           initialize,
    createToolbarElement: createToolbarElement,
    addButtonSet:         addButtonSet,
    addButton:            addButton,
    createButtonElement:  createButtonElement,
    buttonHandler:        buttonHandler,
    observeButtonClick:   observeButtonClick,
    buttonStateHandler:   buttonStateHandler,
    observeStateChanges:  observeStateChanges,
    updateButtonState:    updateButtonState
  };
})());

WysiHat.Toolbar.ButtonSets = {};

WysiHat.Toolbar.ButtonSets.Basic = $A([
  { label: "Bold" },
  { label: "Underline" },
  { label: "Italic" }
]);
