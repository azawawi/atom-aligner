operatorConfig = require './operator-config'
{Point, Range} = require 'atom'

_traverseRanges = (ranges, callback, context = this) ->
  for range in ranges
    for line in range.getRows()
      return output if (output = callback.call(context, line))

module.exports =
###
@name getAlignCharacter
@description
Get the character to align based on text
@param {Editor} editor
@param {number} row
@returns {String} Alignment character
###
getAlignCharacter: (editor, row) ->
  tokenized     = @getTokenizedLineForBufferRow(editor, row)
  languageScope = editor.getRootScopeDescriptor().getScopeChain() or 'base'

  return null unless tokenized

  for token in tokenized.tokens
    tokenValue = token.value.trim()

    config = operatorConfig.getConfig tokenValue, languageScope
    continue unless config

    for tokenScope in token.scopes when tokenScope.match(config.scope)?
      return tokenValue

getAlignCharacterInRanges: (editor, ranges) ->
  _traverseRanges ranges, (line) ->
    character = @getAlignCharacter editor, line
    return character if character
  , this

getOffsets: (editor, character, ranges) ->
  scope   = editor.getRootScopeDescriptor().getScopeChain()
  offsets = []

  _traverseRanges ranges, (line) ->
    tokenized = @getTokenizedLineForBufferRow editor, line
    config    = operatorConfig.getConfig character, scope
    parsed    = @parseTokenizedLine tokenized, character, config

    @setOffsets(offsets, parsed) if parsed.valid
    return
  , this

  return offsets

###
@function
@name parseTokenizedLine
@description
Parsing line with operator
@param {Object} tokenizedLine Tokenized line object from editor display buffer
@param {String} character Character to align
@param {Object} config Character config
@returns {Object} Information about the tokenized line including text before character,
                  text after character, character prefix, offset and if the line is
                  valid
###
parseTokenizedLine: (tokenizedLine, character, config) ->
  afterCharacter = false
  parsed         = []
  parsed.prefix  = null
  whitespaces    = tokenizedLine.firstNonWhitespaceIndex

  section =
    before: ""
    after:  ""

  addToParsed = ->
    section.before = section.before.trimRight()
    section.after  = section.after.trimLeft()
    section.offset = section.before.length

    parsed.push section

    # clear the original section
    section =
      before: ""
      after:  ""

  for token in tokenizedLine.tokens
    tokenValue = token.value

    # To account for leading whitespaces
    if whitespaces > 0
      # if for some reason there is more whitespaces than the length of first token
      if whitespaces > tokenValue.length
        whitespaces -= tokenValue.length
        continue

      tokenValue = tokenValue.substring token.firstNonWhitespaceIndex
      whitespaces -= token.firstNonWhitespaceIndex

    tokenValue = @_formatTokenValue tokenValue, token, tokenizedLine.invisibles

    if operatorConfig.canAlignWith(character, tokenValue.trim(), config) and (not afterCharacter or config.multiple)
      parsed.prefix = operatorConfig.isPrefixed tokenValue.trim(), config

      if config.multiple
        addToParsed()

      afterCharacter = true
      continue

    variable           = if afterCharacter and not config.multiple then "after" else "before"
    section[variable] += tokenValue

  # Add the last section to parsed
  addToParsed()
  parsed.valid = afterCharacter

  return parsed

setOffsets: (offsets, parsedObjects) ->
  for parsedObject, i in parsedObjects
    offsets[i] ?= parsedObject.offset

    if parsedObject.offset > offsets[i]
      offsets[i] = parsedObject.offset

###
@function
@name getSameIndentationRange
@description To get the start and end line number of the same indentation
@param {Editor} editor Active editor
@param {Integer} row Row to match
@returns {Object} An object with the start and end line
###
getSameIndentationRange: (editor, row, character) ->
  start = row - 1
  end   = row + 1

  tokenized = @getTokenizedLineForBufferRow editor, row
  scope     = editor.getRootScopeDescriptor().getScopeChain()
  config    = operatorConfig.getConfig character, scope

  parsed    = @parseTokenizedLine tokenized, character, config
  indent    = editor.indentationForBufferRow row
  total     = editor.getLineCount()
  hasPrefix = parsed.prefix

  offsets    = []
  startPoint = new Point(row, 0)
  endPoint   = new Point(row, Infinity)

  @setOffsets offsets, parsed

  while start > -1 or end < total
    if start > -1
      startLine = @getTokenizedLineForBufferRow editor, start

      if startLine? and editor.indentationForBufferRow(start) is indent
        if atom.config.get('aligner.alignAcrossComments') and startLine.isComment()
          start -= 1

        else if (parsed = @parseTokenizedLine startLine, character, config) and parsed.valid
          @setOffsets offsets, parsed
          startPoint.row  = start
          hasPrefix       = true if not hasPrefix and parsed.prefix
          start          -= 1

        else
          start = -1

      else
        start = -1

    if end < total + 1
      endLine = @getTokenizedLineForBufferRow editor, end

      if endLine? and editor.indentationForBufferRow(end) is indent
        if atom.config.get('aligner.alignAcrossComments') and endLine.isComment()
          end += 1

        else if (parsed = @parseTokenizedLine endLine, character, config) and parsed.valid
          @setOffsets offsets, parsed
          endPoint.row  = end
          hasPrefix     = true if not hasPrefix and parsed.prefix
          end          += 1

        else
          end = total + 1

      else
        end = total + 1

  if hasPrefix
    offsets = offsets.map (item) -> item + 1

  return {
    range:  new Range(startPoint, endPoint),
    offset: offsets
  }

getTokenizedLineForBufferRow: (editor, row) ->
  editor.displayBuffer.tokenizedBuffer.tokenizedLineForRow(row)

_formatTokenValue: (value, token, invisibles) ->
  return value unless token.hasInvisibleCharacters

  if token.firstNonWhitespaceIndex?
    leading = value.substring(0, token.firstNonWhitespaceIndex)
    leading = @_formatInvisibleSpaces leading, invisibles
    value = leading + value.substring(token.firstNonWhitespaceIndex)

  # To convert trailing whitespace invisible to whitespace
  if token.firstTrailingWhitespaceIndex?
    trailing = value.substring(token.firstTrailingWhitespaceIndex)
    trailing = @_formatInvisibleSpaces trailing, invisibles
    value = value.substring(0, token.firstTrailingWhitespaceIndex) + trailing

  return value

_formatInvisibleSpaces: (string, invisibles) ->
  if invisibles.space?
    string = string.replace(new RegExp(invisibles.space, 'g'), " ")

  if invisibles.tab?
    string = string.replace(new RegExp(invisibles.tab, 'g'), "\t")

  return string
