#
# Description:
#   XML processing functions (e.g. tag tokenizing, etc.), including a minimal but functional parser.
#
load(":utils.bzl", "strings")

#
# Definitions
#
# element_token
# struct(
#   label -> the element label (e.g. "<foo>" has the label "foo")
#   start -> the absolute start of this element token in the string, i.e. the index of "<" for this token.
#   end -> the absolute end of the element token in the string, i.e. the index of ">" for this token.
#   skipped -> The number of characters from the provided "start_from" substring index to the start index.
#              e.g. for "<foo>  <bar>" the skipped for "foo" is 0, and the skipped for "bar" would be 2
# )
#
#

_element_kind_enum = struct(
    start = "START",  # A start tag (e.g. "<foo>")
    end = "END", # An end-tag (e.g. "</foo>")
    empty = "EMPTY", # A tag without children or string content (e.g. "<blah />")
    xml = "XML_PREFIX" # An xml prefix tag (e.g. "<?xml version="1.0" encoding="UTF-8"?>")
)

# Walks back from just before the tag end to the end of the attribute text.
def _process_element_tail(xml, label, cursor, attr_start, tag_end):
    for index in range(cursor-1, attr_start, -1):
        if xml[index].isspace():
            pass
        else:
            attr_end = index + 1 # end is just after the last character of the
            return struct(
                label = label,
                end = tag_end,
                attrs = struct(start = attr_start, end = attr_end))

# Description:
#   Scans the string until a ">" character is found that is not within quotes, and returns a structure with the
#   label of the tag, the start and end indicies of the attributes section if any, and the tag end.
#   If an xml string passed in runs out of characters before terminating the tag, the code will throw an index
#   out of bounds error.
def _find_element_end(xml, tag_start_index):
    label_start = tag_start_index+1
    if xml[tag_start_index:label_start] != "<":
        fail("Assertion error, invalid xml passed to function. Substring should start with \"<\".   Please report.")
    cursor = label_start
    label = ""
    # Grab the basic label and section off attributes (or close the tag)
    for _ in range(cursor, len(xml)+1): # Invoke an IOB if we exceed the string length.
        if xml[cursor].isspace():
            # found label but tag isn't fully processed, so increment and break out of this section.
            label = xml[label_start:cursor]
            cursor += 1
            break;
        elif xml[cursor] == ">":
            # We found tag end, so short-circuit.
            return struct(
                label = xml[label_start:cursor], end = cursor+1, attrs = struct(start = 0, end = 0))
        elif xml[cursor:cursor+2] == "/>":
            # We found tag end for an empty tag, so short-circuit.
            label = xml[label_start:cursor]
            cursor += 2
            return struct(label = label, end = cursor, attrs = struct(start = 0, end = 0))
        cursor += 1

    # At this point, we are past the label.  Eat up whitespace.
    for _ in range(cursor, len(xml)+1): # Invoke an IOB if we exceed the string length.
        if not xml[cursor].isspace():
            break
        cursor += 1

    if xml[cursor] == ">":
        # Found an end after the label, before any attributes.
        return struct(label = label, end = cursor+1, attrs = struct(start = 0, end = 0))
    if xml[cursor:cursor+2] == "/>" :
        # Found an end after the label, before any attributes.
        return struct(label = label, end = cursor+2, attrs = struct(start = 0, end = 0))

    #Found an attribute section, so grab it.
    attr_start = cursor
    in_quotes = False
    for _ in range(cursor, len(xml)+1): # Invoke an IOB if we exceed the string length.
        if xml[cursor] == "\"":
            in_quotes = not in_quotes
        elif not in_quotes:
            if xml[cursor] == ">":
                return _process_element_tail(xml, label, cursor, attr_start, tag_end = cursor + 1)
            elif xml[cursor:cursor + 2] == "/>":
                return _process_element_tail(xml, label, cursor, attr_start, tag_end = cursor + 2)
            elif xml[cursor:cursor + 2] == "?>":
                return _process_element_tail(xml, label, cursor, attr_start, tag_end = cursor + 2)
        cursor += 1

    fail("""Badly formed document has a no end to the tag. Please file a bug: "%s" """ % xml)

# Scans forward in the xml, looking for the first non-comment xml element start.
def _find_element_start(xml, start_from):
    cursor = xml.find("<", start_from)
    if cursor == -1:
        return -1 # no more xml elements in this text.

    # Scan for comments and CDATA sections between elements.
    # Note these are similar, but slightly different, as comment scanning needs to check
    # for "--" within the comment, which is invalid. CNAMEs just end when ]]> is found, but
    # ]] is valid.
    for _ in range(cursor, len(xml)):
        # Need to check for multiple comment sections.
        if len(xml) - cursor > 4 and xml[cursor:cursor+4] == "<!--":
            cursor += 4
            # Found a comment, scan forward to the comment end.
            for _ in range(cursor, len(xml)):
                if xml[cursor] == "-" and xml[cursor+1] == "-":
                    # maybe comment end?
                    if xml[cursor+2] == ">":
                        # found comment end
                        cursor = xml.find("<", cursor + 3)
                        if cursor == -1:
                            return -1 # no more tags in this text.
                        break
                    else:
                        fail("XML comments may not contain the string \"--\". %s" % xml)
                else:
                    cursor += 1
        elif len(xml) - cursor > 9 and xml[cursor:cursor+9] == "<![CDATA[":
            cursor += 9
            # Found a CDATA section, scan forward to the CEND.
            for _ in range(cursor, len(xml)):
                if cursor+3 <= len(xml) and xml[cursor:cursor+3] == "]]>":
                    cursor = xml.find("<", cursor + 3)
                    if cursor == -1:
                        return -1 # no more xml elements in this text.
                    break # Found CEND, reset start and cursor and break
                else:
                    cursor += 1
        else:
            break
    return cursor

# Description
#    Returns the next tag (optionally within a substring), including its label and start/end.
#    The start/end are relative to the start of the xml string, not the substring start index,
#    but the search is constrained to the substring.
#
#    This implementation skips over xml comment sections, which are NOT represented as a element, and
#    CNAME sections, which are also not represented as an element.  This is technically incorrect, as
#    CNAME sections are part of the XML document, but we are not handling them.
#
#    Note: this is a bit inefficient, creating two structs, but the code to do it in one was unreadable.
def _next_element(xml, start_from = 0):
    start = _find_element_start(xml, start_from)
    if start == -1:
        return None # no more xml elmements in this text.

    tag_internals = _find_element_end(xml, start)
    label = tag_internals.label

    # Process the kind/type of the element (and reset a few sizes, so we can target the internal structure.
    kind = elements.kind.start
    if label.startswith("/"):
        label = label[1:]
        kind = elements.kind.end
    elif xml[tag_internals.end-2:tag_internals.end] == "/>": # element tag ends in /> instead of >
        kind = elements.kind.empty
    elif label.startswith("?"): # This is a prefix, special element.
        label = label[1:]
        kind = elements.kind.xml

    return struct(
        label = label,
        start = start,
        end = tag_internals.end,
        skipped = start - start_from,
        kind = kind,
        attrs = xml[tag_internals.attrs.start:tag_internals.attrs.end],
    )

# Description:
#   Returns an array of element_token structs, containing the start/end and label of the element token, as well as
#   the number of characters from the substring strat.
#
#   This tokenizer generally is implemented as an iterative string-scanner, as Starlark has no recursion, and it
#   isn't clear how much memory would be chewed up by repeated chopping of the string into bits in the internals.
#   The parser can consume the token array and walk the string, while it builds the tree (which is its API, so at
#   least there it has to make a bunch of objects).  This may be pre-optimization.  But given that iteration is
#   the only technical option, avoiding extra string building seemed wise.
def _element_token_array(xml):
    tokens = []
    prev = None
    index = 0
    for x in range(0, len(xml)):
        cursor = prev.end if prev else 0
        token = elements.next(xml, cursor)
        if not token:
            break
        tokens += [token]
        prev = token
    return tokens

# Description:
#   Creates a new xml node struct used in the tree.
def _new_node(label, content = None, children = []):
    return struct(label = label, content = content, children = children)

# Description:
#   Returns the first node with the given label, if it's present in the children of the given node.
def _find_first(node, *labels):
    stack = []
    current = node
    for label in list(labels):
        for child in current.children:
            if child.label == label:
                stack.append(child.label)
                current = child
                break
    return current if list(labels) == stack else None

# Description:
#   A simplified maven XML parser, which ignores namespaces, mostly ignores (but preserves the text of) xml attributes.
#
#   This parser is limited, in that it:
#     * does not support mixed content (elements with both non-whitespace text content and child elements)
#     * does not support xml namespaces
#     * does not preserve comments in the element tree
#     * does not keep a dictionary of attributes.
#     * does not fully validate
#       - It does some in-process validation but doesn't check, for instance, that there is a single standard root
#
#
#   The parser scans the text stream, tokenizing it, and assembling the resulting tokens into nodes in an element
#   tree.  Each node is defined as follows:
#
#   struct(
#     label -> The tag name of this element
#     content -> Text content if it contains any
#     children[] -> A list of child nodes (if any)
#   )
#
# Returns:
#   An element tree with an xml_node structure defined above.
def _parse(xml_text):
    path = [] # The current node in the tree, (e.g. ["project", "dependencies", "dependency[0]"]
    tokens = elements.token_array(xml_text)
    root = xml.new_node(label = None, content = None, children = [])
    path += [root]
    prev = None
    for i in range(0, len(tokens)):
        token = tokens[i]
        if token.kind == elements.kind.xml:
            path[-1].children.append(xml.new_node(label = token.label))
        elif token.kind == elements.kind.start:
            next = tokens[i+1]
            if next.label == token.label and next.kind == elements.kind.end:
                content = xml_text[next.start - next.skipped:next.start]
                # No child elements, so treat the prefix of the next token as CNAME content.
                node = xml.new_node(label = token.label, content = content)
            else:
                # Has child elements, so ignore text content
                node = xml.new_node(label = token.label, children = [])
            path[-1].children.append(node)
            path.append(node)
        elif token.kind == elements.kind.end:
            popped = path.pop()
            if popped.label != token.label:
                fail("Unbalanced xml tree: closing tag </%s> incorrectly matched with <%s> in xml %s." % (
                    token.label, popped.label, xml_text))
        elif token.kind == elements.kind.empty:
            path[-1].children.append(xml.new_node(label = token.label)) # Attach, but don't bother to push/pop.
        prev = token
    return root

elements = struct(
    kind = _element_kind_enum,
    next = _next_element,
    token_array = _element_token_array,
)

xml = struct(
    parse = _parse,
    new_node = _new_node,
    find_first = _find_first,
)

for_testing = struct(
    find_element_end = _find_element_end,
    find_element_start = _find_element_start
)
