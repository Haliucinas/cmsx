
{last, find} = require './helpers'

$ = require './symbols'

stringEscape = require './stringescape'

entityDecode = require './entitydecode'

module.exports = exports = serialise = (parseTree) ->
  new Serialiser().serialise(parseTree)

class Serialiser
  serialise: (parseTree, @opts = {}) ->
    if parseTree.children and
    parseTree.children.length and
    parseTree.children[0].type is $.CJSX_PRAGMA
      @domObject = parseTree.children[0].value
    else
      @domObject = 'React.DOM'

    @serialiseNode(parseTree)

  serialiseNode: (node) ->
    unless nodeSerialisers[node.type]?
      throw new Error("unknown parseTree node type #{node.type}")

    serialised = nodeSerialisers[node.type].call(this, node)

    unless typeof serialised is 'string' or serialised is null
      throw new Error("serialiser #{node.type} didn\'t return a string")

    serialised

  serialiseAttributePairs: (children) ->
    # whitespace (particularly newlines) must be maintained
    # to ensure line number parity

    # sort children into whitespace and semantic (non whitespace) groups
    [whitespaceChildren, semanticChildren] = children.reduce((partitionedChildren, child) ->
      if child.type is $.CJSX_WHITESPACE
        partitionedChildren[0].push child
      else
        partitionedChildren[1].push child
      partitionedChildren
    , [[],[]])

    indexOfLastSemanticChild = children.lastIndexOf(last(semanticChildren))

    isBeforeLastSemanticChild = (childIndex) ->
      childIndex < indexOfLastSemanticChild

    if semanticChildren.length
      serialisedChildren = for child, childIndex in children
        serialisedChild = @serialiseNode child
        if child.type is $.CJSX_WHITESPACE
          if containsNewlines(serialisedChild)
            if isBeforeLastSemanticChild(childIndex)
              # escaping newlines within attr object helps avoid
              # parse errors in tags which span multiple lines
              serialisedChild.replace('\n',' \\\n')
            else
              # but escaped newline at end of attr object is not allowed
              serialisedChild
          else
            null # whitespace without newlines is not significant
        else if isBeforeLastSemanticChild(childIndex)
          serialisedChild+', '
        else
          serialisedChild

      '{'+serialisedChildren.join('')+'}'
    else
      null

genericBranchSerialiser = (node) ->
  node.children
    .map((child) => @serialiseNode child)
    .join('')

genericLeafSerialiser = (node) -> node.value

tagConvention = /^[a-z]|\-/

nodeSerialisers =
  ROOT: genericBranchSerialiser

  CJSX_PRAGMA: -> "`/** @jsx #{@domObject} */`"

  CJSX_EL: (node) ->
    serialisedAttribute = null
    serialisedChildren = []
    accumulatedWhitespace = ''

    for child in node.children
      serialisedChild = @serialiseNode child
      if child? # filter empty text nodes
        if serialisedChild.length is 0 or WHITESPACE_ONLY.test serialisedChild
          accumulatedWhitespace += serialisedChild
        else if child.type is $.CJSX_ATTRIBUTES
          serialisedAttribute = serialisedChild
        else
          serialisedChildren.push(accumulatedWhitespace + serialisedChild)
          accumulatedWhitespace = ''

    if serialisedChildren.length
      serialisedChildren[serialisedChildren.length-1] += accumulatedWhitespace
      accumulatedWhitespace = ''

    element = '"'+node.value+'"'
    "{tag: #{element}, attrs: #{serialisedAttribute}, children: [#{joinList(serialisedChildren)}]}"

  CJSX_COMMENT: (node) ->
    ''

  CJSX_ESC: (node) ->
    childrenSerialised = node.children
      .map((child) => @serialiseNode child)
      .join('')
    '('+childrenSerialised+')'

  CJSX_ATTRIBUTES: (node) ->
    @serialiseAttributePairs(node.children) or '{}'

  CJSX_ATTR_PAIR: (node) ->
    node.children
      .map((child) => @serialiseNode child)
      .join(': ')

  CJSX_ATTR_SPREAD: (node) ->
    node.value

  # leaf nodes
  CS: genericLeafSerialiser
  CS_COMMENT: genericLeafSerialiser
  CS_HEREDOC: genericLeafSerialiser
  CS_STRING: genericLeafSerialiser
  CS_REGEX: genericLeafSerialiser
  CS_HEREGEX: genericLeafSerialiser
  JS_ESC: genericLeafSerialiser
  CJSX_WHITESPACE: genericLeafSerialiser

  CJSX_TEXT: (node) ->
    # trim whitespace only if it includes a newline
    text = node.value
    if containsNewlines(text)
      if WHITESPACE_ONLY.test text
        text
      else
        # this is not very efficient
        leftSpace = text.match TEXT_LEADING_WHITESPACE
        rightSpace = text.match TEXT_TRAILING_WHITESPACE

        if leftSpace
          leftTrim = text.indexOf('\n')
        else
          leftTrim = 0

        if rightSpace
          rightTrim = text.lastIndexOf('\n')+1
        else
          rightTrim = text.length

        trimmedText = text.substring(leftTrim, rightTrim)
        # decode html entities to chars
        # escape string special chars except newlines
        # output to multiline string literal for line parity
        escapedText = stringEscape(entityDecode(trimmedText), preserveNewlines:  true)
        '"""'+escapedText+'"""'

    else
      if text == ''
        null # this text node will be omitted
      else
        # decode html entities to chars
        # escape string special chars
        '"'+stringEscape(entityDecode(text))+'"'

  CJSX_ATTR_KEY: genericLeafSerialiser
  CJSX_ATTR_VAL: genericLeafSerialiser

firstNonWhitespaceChild = (children) ->
  find.call children, (child) ->
    child.type isnt $.CJSX_WHITESPACE

containsNewlines = (text) -> text.indexOf('\n') > -1

joinList = (items) ->
  output = items[items.length-1]
  i = items.length-2

  while i >= 0
    if output.charAt(0) is '\n'
      output = items[i]+','+output
    else
      output = items[i]+', '+output
    i--
  output?.replace(/^[\n\s]+/, '') or ''


SPACES_ONLY = /^\s+$/

WHITESPACE_ONLY = /^[\n\s]+$/

# leading and trailing whitespace which contains a newline
TEXT_LEADING_WHITESPACE = /^\s*?\n\s*/
TEXT_TRAILING_WHITESPACE = /\s*?\n\s*?$/

exports.Serialiser = Serialiser
exports.nodeSerialisers = nodeSerialisers
