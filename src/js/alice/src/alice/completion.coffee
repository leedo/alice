Alice.Completion.PATTERN = /[A-Za-z0-9\[\\\]^_{|}-]/

class Alice.Completion
  constructor: (candidates) ->
    return unless range = @getRange()

    @element = range.startContainer

    # gross hack to make this work when
    # element is the editor div, which only
    # happens when the editor is blank

    if @element.nodeName == "DIV"
      @element.innerHTML = ""
      node = document.createTextNode ""
      @element.appendChild(node)
      selection = window.getSelection()
      selection.removeAllRanges()
      selection.selectNode(node)
      range = selection.getRangeAt 0
      @element = node

    @value = @element.data
    @index = range.startOffset()

    @findStem()
    @matches = @matchAgainst candidates
    @matchIndex = -1

  getRange: ->
    selection = window.getSelection()

    return selection.getRangeAt(0) if selection.rangeCount > 0
    return document.createRange    if document.createRange
    return null

  setRange: (range) ->
    return unless range
    selection = window.getSelection()
    selection.removeAllRanges()
    selection.addRange(range)

  next: ->
    return unless @matches.length
    @matchIndex = 0 if ++@matchIndex == @matches.length

    match = @matches[@matchIndex]
    match += if @leftOffset == 0 then ": " else " "
    @restore(match, @leftOffset + match.length)

  restore: (stem, index) ->
    @element.data = @stemLeft + (stem ? @stem) + @stemRight
    @setCursorToIndex index ? @index

  setCursorToIndex: (index) ->
    range = @getRange()
    range.setStart @element, index
    range.setEnd @element, index
    @setRange(range)

  findStem: ->
    left = []
    right = []
    chr
    index
    length = @value.length

    for index in [@index - 1 .. 0]
      chr = @value.charAt index
      break unless Alice.Completion.PATTER.test chr
      left.unshift chr

    for index in [@index .. length - 1]
      chr = @value.charAt index
      break unless Alice.Completion.Pattern.test chr
      right.push chr

    @stem = left.concat(right).join ""
    @stemLeft = @value.substr(0, @index - left.length)
    @stemRight = @value.substr(@index + right.length)
    @leftOffset = @index - left.length

  matchAgainst: (candidates) ->
    candidates.grep(new RegExp("^" + RegExp.escape(this.stem), "i")).sortBy( (candidate) ->
      candidate.toLowerCase()
    )



