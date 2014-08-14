#= require trix/utilities/object
#= require trix/models/block
#= require trix/models/splittable_list
#= require trix/models/location_range

class Trix.Document extends Trix.Object
  @fromJSON: (documentJSON) ->
    blocks = for blockJSON in documentJSON
      Trix.Block.fromJSON blockJSON
    new this blocks

  @fromHTML: (html, options) ->
    Trix.HTMLParser.parse(html, options).getDocument()

  @fromString: (string, textAttributes) ->
    text = Trix.Text.textForStringWithAttributes(string, textAttributes)
    new this [new Trix.Block text]

  constructor: (blocks = []) ->
    super
    @editDepth = 0
    @editCount = 0
    @blockList = new Trix.SplittableList blocks

  copy: ->
    new @constructor @blockList.toArray()

  edit = (name, fn) -> ->
    @beginEditing()
    fn.apply(this, arguments)

    console.group(name)
    console.log(format(object)...) for object in arguments
    console.groupEnd()

    @endEditing()

  format = (object) ->
    if (value = object?.toConsole?())?
      ["%o%c%s%c", object, "color: #888", value, "color: auto"]
    else if typeof object is "string"
      ["%s", object]
    else
      ["%o", object]

  edit: edit "edit", (fn) -> fn()

  beginEditing: ->
    if @editDepth++ is 0
      @editCount++
      console.group("Edit operation #{@editCount}")
    this

  endEditing: ->
    if --@editDepth is 0
      console.groupEnd()
      @delegate?.didEditDocument?(this)
    this

  insertDocumentAtLocationRange: edit "insertDocumentAtLocationRange", (document, locationRange) ->
    position = @blockList.findPositionAtIndexAndOffset(locationRange.index, locationRange.offset)
    @removeTextAtLocationRange(locationRange)
    @blockList = @blockList.insertSplittableListAtPosition(document.blockList, position)

  replaceDocument: edit "replaceDocument", (document) ->
    @blockList = document.blockList.copy()

  insertPlaceholderBlockAtLocationRange: edit "insertPlaceholderBlockAtLocationRange", (locationRange) ->
    document = new Trix.Document [Trix.Block.createPlaceholder()]
    @insertDocumentAtLocationRange(document, locationRange)

  insertTextAtLocationRange: edit "insertTextAtLocationRange", (text, locationRange) ->
    @removeTextAtLocationRange(locationRange)
    if @blockList.length is 0
      block = new Trix.Block text
      @blockList = @blockList.insertObjectAtIndex(block, 0)
    else
      @blockList = @blockList.editObjectAtIndex locationRange.index, (block) ->
        block.copyWithText(block.text.insertTextAtPosition(text, locationRange.offset))

  removeTextAtLocationRange: edit "removeTextAtLocationRange", (locationRange) ->
    return if locationRange.isCollapsed()

    leftIndex = locationRange.start.index
    leftBlock = @getBlockAtIndex(leftIndex)
    leftText = leftBlock.text.getTextAtRange([0, locationRange.start.offset])

    rightIndex = locationRange.end.index
    rightBlock = @getBlockAtIndex(rightIndex)
    rightText = rightBlock.text.getTextAtRange([locationRange.end.offset, rightBlock.getLength()])

    text = leftText.appendText(rightText)
    block = leftBlock.copyWithText(text)
    blocks = @blockList.toArray()
    affectedBlockCount = rightIndex + 1 - leftIndex

    if block.isEmpty()
      blocks.splice(leftIndex, affectedBlockCount)
    else
      blocks.splice(leftIndex, affectedBlockCount, block)

    @blockList = new Trix.SplittableList blocks

  moveTextFromLocationRangeToPosition: edit "moveTextFromLocationRangeToPosition", (locationRange, position) ->
    range = @rangeFromLocationRange(locationRange)
    return if range[0] <= position <= range[1]
    document = @getDocumentAtLocationRange(locationRange)
    @removeTextAtLocationRange(locationRange)
    position -= document.getLength() if range[0] < position
    @insertDocumentAtLocationRange(document, @locationRangeFromPosition(position))

  addAttributeAtLocationRange: edit "addAttributeAtLocationRange", (attribute, value, locationRange) ->
    if Trix.attributes[attribute]?.block
      if locationRange.isCollapsed()
        @blockList = @blockList.editObjectAtIndex locationRange.index, (block) ->
          block.addAttribute(attribute, value)
      else
        range = @rangeFromLocationRange(locationRange)
        @blockList = @blockList.transformObjectsInRange range, (block) ->
          block.addAttribute(attribute, value)
    else
      @eachBlockAtLocationRange locationRange, (block, range, index) =>
        if range[0] isnt range[1]
          @blockList = @blockList.editObjectAtIndex index, ->
            block.copyWithText(block.text.addAttributeAtRange(attribute, value, range))

  addAttribute: edit "addAttribute", (attribute, value) ->
    @eachBlock (block, index) =>
      @blockList = @blockList.editObjectAtIndex (index), ->
        block.addAttribute(attribute, value)

  removeAttributeAtLocationRange: edit "removeAttributeAtLocationRange", (attribute, locationRange) ->
    @eachBlockAtLocationRange locationRange, (block, range, index) =>
      if Trix.attributes[attribute]?.block
        @blockList = @blockList.editObjectAtIndex index, ->
          block.removeAttribute(attribute)
      else if range[0] isnt range[1]
        @blockList = @blockList.editObjectAtIndex index, ->
          block.copyWithText(block.text.removeAttributeAtRange(attribute, range))

  updateAttributesForAttachment: edit "updateAttributesForAttachment", (attributes, attachment) ->
    locationRange = @getLocationRangeOfAttachment(attachment)
    text = @getTextAtIndex(locationRange.index)
    @blockList = @blockList.editObjectAtIndex locationRange.index, (block) ->
      block.copyWithText(text.updateAttributesForAttachment(attributes, attachment))

  trimLeft: edit "trimLeft", (string = " ") ->
    text = @getTextAtIndex(0)
    textLength = text.getLength()
    range = [0, string.length]
    if text.getStringAtRange(range) is string
      @blockList = @blockList.editObjectAtIndex 0, (block) ->
        block.copyWithText(text.removeTextAtRange(range))

  trimRight: edit "trimRight", (string = " ") ->
    index = @blockList.length - 1
    text = @getTextAtIndex(index)
    textLength = text.getLength()
    range = [textLength - string.length, textLength]
    if text.getStringAtRange(range) is string
      @blockList = @blockList.editObjectAtIndex index, (block) ->
        block.copyWithText(text.removeTextAtRange(range))

  getDocumentAtLocationRange: (locationRange) ->
    range = @rangeFromLocationRange(locationRange)
    blocks = @blockList.getSplittableListInRange(range).toArray()
    if blocks.length is 0
      # Should the constructor do this?
      blocks.push(new Trix.Block)
    new @constructor blocks

  getStringAtLocationRange: (locationRange) ->
    @getDocumentAtLocationRange(locationRange).toString()

  getBlockAtIndex: (index) ->
    @blockList.getObjectAtIndex(index)

  getTextAtIndex: (index) ->
    @getBlockAtIndex(index)?.text

  getLength: ->
    @blockList.getEndPosition()

  eachBlock: (callback) ->
    @blockList.eachObject(callback)

  eachBlockAtLocationRange: (range, callback) ->
    if range.isInSingleIndex()
      block = @getBlockAtIndex(range.index)
      textRange = [range.start.offset, range.end.offset]
      callback(block, textRange, range.index)
    else
      range.eachIndex (index) =>
        block = @getBlockAtIndex(index)

        textRange = switch index
          when range.start.index
            [range.start.offset, block.text.getLength()]
          when range.end.index
            [0, range.end.offset]
          else
            [0, block.text.getLength()]

        callback(block, textRange, index)

  getCommonAttributesAtLocationRange: (locationRange) ->
    if locationRange.isCollapsed()
      @getCommonAttributesAtLocation(locationRange.start)
    else
      textAttributes = []
      blockAttributes = []

      @eachBlockAtLocationRange locationRange, (block, textRange) ->
        textAttributes.push(block.text.getCommonAttributesAtRange(textRange))
        blockAttributes.push(block.getAttributes())

      Trix.Hash.fromCommonAttributesOfObjects(textAttributes)
        .merge(Trix.Hash.fromCommonAttributesOfObjects(blockAttributes))
        .toObject()

  getCommonAttributesAtLocation: ({index, offset}) ->
    block = @getBlockAtIndex(index)
    return {} unless block

    commonAttributes = block.getAttributes()
    attributes = block.text.getAttributesAtPosition(offset)
    attributesLeft = block.text.getAttributesAtPosition(offset - 1)
    inheritableAttributes = (key for key, value of Trix.attributes when value.inheritable)

    for key, value of attributesLeft
      if value is attributes[key] or key in inheritableAttributes
        commonAttributes[key] = value

    commonAttributes

  getAttachmentPieces: ->
    attachmentPieces = []
    @blockList.eachObject ({text}) ->
      attachmentPieces = attachmentPieces.concat(text.getAttachmentPieces())
    attachmentPieces

  getAttachments: ->
    piece.attachment for piece in @getAttachmentPieces()

  getLocationRangeOfAttachment: (attachment) ->
    for {text}, index in @blockList.toArray()
      if range = text.getRangeOfAttachment(attachment)
        return new Trix.LocationRange {index, offset: range[0]}, {index, offset: range[1]}

  getAttachmentById: (id) ->
    for {text} in @blockList.toArray()
      if attachment = text.getAttachmentById(id)
        return attachment

  getAttachmentPieceForAttachment: (attachment) ->
    return piece for piece in @getAttachmentPieces() when piece.attachment is attachment

  attachmentIsImage: (attachment) ->
    attachmentPiece = @getAttachmentPieceForAttachment(attachment)
    attachmentPiece?.isImage()

  expandedLocationRangeForBlockTransformation: (locationRange) ->
    start = { index: locationRange.start.index, offset: locationRange.start.offset }
    end = { index: locationRange.end.index, offset: locationRange.end.offset }

    unless start.offset is 0
      startString = @getTextAtIndex(start.index).getStringAtRange([0, start.offset])
      startOffset = startString.lastIndexOf("\n")
      start.offset = if startOffset isnt -1 then startOffset else 0

    endText = @getTextAtIndex(end.index)
    unless end.offset is (endLength = endText.getLength())
      endString = endText.getStringAtRange([end.offset, endLength])
      endOffset = endString.indexOf("\n")
      end.offset = if endOffset isnt -1 then end.offset + endOffset + 1 else endLength

    new Trix.LocationRange start, end

  rangeFromLocationRange: (locationRange) ->
    leftPosition = @blockList.findPositionAtIndexAndOffset(locationRange.start.index, locationRange.start.offset)
    rightPosition = @blockList.findPositionAtIndexAndOffset(locationRange.end.index, locationRange.end.offset) unless locationRange.isCollapsed()
    [leftPosition, rightPosition ? leftPosition]

  locationRangeFromPosition: (position) ->
    new Trix.LocationRange @blockList.findIndexAndOffsetAtPosition(position)

  toString: ->
    @blockList.toString()

  toJSON: ->
    @blockList.toJSON()

  toConsole: ->
    JSON.stringify(JSON.parse(block.text.toConsole()) for block in @blockList.toArray())
