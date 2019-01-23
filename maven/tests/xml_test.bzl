load(":testing.bzl", "asserts", "test_suite")
load("//maven:xml.bzl", "elements", "xml", "for_testing")


XML_FRAGMENT = """
   <foo>
     <bar>blah> </bar> <blah/><blah /> <blah foo=\"bar\" /></foo>

"""

def next_element_basic_test(env):
    asserts.equals(env,
        expected = struct(label = "foo", start = 4, end = 9, skipped = 4, kind = elements.kind.start, attrs = ""),
        actual = elements.next(XML_FRAGMENT),
        message = "First token: <foo>")
    asserts.equals(env,
        expected = struct(label = "bar", start = 15, end = 20, skipped = 6, kind = elements.kind.start, attrs = ""),
        actual = elements.next(XML_FRAGMENT, 9),
        message = "Second token: <bar>")
    asserts.equals(env,
        expected = struct(label = "bar", start = 26, end = 32, skipped = 6, kind = elements.kind.end, attrs = ""),
        actual = elements.next(XML_FRAGMENT, 20),
        message = "Third token: </bar>")
    # same as previous, but get the preceding text.
    token = elements.next(XML_FRAGMENT, 20)
    asserts.equals(env,
        expected = "blah> ",
        actual = XML_FRAGMENT[token.start-token.skipped:token.start],
        message = "Third token's skipped text.")
    asserts.equals(env,
        expected = struct(label = "blah", start = 33, end = 40, skipped = 1, kind = elements.kind.empty, attrs = ""),
        actual = elements.next(XML_FRAGMENT, 32),
        message = "Fourth token: <blah/>")
    asserts.equals(env,
        expected = struct(label = "blah", start = 40, end = 48, skipped = 0, kind = elements.kind.empty, attrs = ""),
        actual = elements.next(XML_FRAGMENT, 40),
        message = "Fifth token: <blah />")
    asserts.equals(env,
        expected = struct(label = "blah", start = 49, end = 67, skipped = 1, kind = elements.kind.empty, attrs = "foo=\"bar\""),
        actual = elements.next(XML_FRAGMENT, 48),
        message = "Sixth token: <blah foo=\"bar\" />")
    asserts.equals(env,
        expected = struct(label = "foo", start = 67, end = 73, skipped = 0, kind = elements.kind.end, attrs = ""),
        actual = elements.next(XML_FRAGMENT, 67),
        message = "Seventh token: </foo>")

def find_element_start_test(env):
    asserts.equals(env, 2, for_testing.find_element_start("""  <foo>""", 0))
    asserts.equals(env, 14, for_testing.find_element_start(""" <!-- blah --><foo>""", 0))
    asserts.equals(env, 15, for_testing.find_element_start(""" <!-- blah --> <foo>""", 0))
    asserts.equals(env, 27, for_testing.find_element_start(""" <!-- blah --><!-- baz --> <barf />""", 0))
    asserts.equals(env, 28, for_testing.find_element_start(""" <!-- blah --> <!-- baz --> <barf />""", 0))


def find_element_end_test(env):
    asserts.equals(env,
        expected = struct(attrs = struct(end = 0, start = 0), end = 7, label = "foo"),
        actual = for_testing.find_element_end("""  <foo>""", 2))
    asserts.equals(env,
        expected = struct(attrs = struct(end = 0, start = 0), end = 11, label = "foo"),
        actual = for_testing.find_element_end("""  <foo    >""", 2))
    asserts.equals(env,
        expected = struct(attrs = struct(end = 17, start = 7), end = 18, label = "foo"),
        actual = for_testing.find_element_end("""  <foo blah="foo">""", 2))
    asserts.equals(env,
        expected = struct(attrs = struct(end = 0, start = 0), end = 8, label = "foo"),
        actual = for_testing.find_element_end("""  <foo/>""", 2))
    asserts.equals(env,
        expected = struct(attrs = struct(end = 0, start = 0), end = 9, label = "foo"),
        actual = for_testing.find_element_end("""  <foo />""", 2))
    asserts.equals(env,
        expected = struct(attrs = struct(end = 18, start = 8), end = 20, label = "?xml"),
        actual = for_testing.find_element_end("""  <?xml blah="foo"?>""", 2))
    asserts.equals(env,
        expected = struct(attrs = struct(end = 18, start = 8), end = 21, label = "?xml"),
        actual = for_testing.find_element_end("""  <?xml blah="foo" ?>""", 2))
    asserts.equals(env,
        expected = struct(attrs = struct(end = 17, start = 7), end = 18, label = "foo"),
        actual = for_testing.find_element_end("""  <foo blah="a>b">""", 2))


XML_DOC = """
<?xml version="1.0" encoding="UTF-8"  ?>
<foo xmlns="blah"><!-- >  --><!-- another -->
  <bar>4.0.0</bar>
  <qof foo="blah>foo" />
  <blah a="b">
    <baz q="r" />
  </blah a="b">      </foo>
"""

def finds_xml_header_test(env):
    asserts.equals(env,
        expected = struct(
            label = "xml",
            start = 1,
            end = 41,
            skipped = 1,
            kind = elements.kind.xml,
            attrs = "version=\"1.0\" encoding=\"UTF-8\""),
        actual = elements.next(XML_DOC),
        message = "First token: foo")

def skips_comments_test(env):
    asserts.equals(env,
        expected = struct(
            label = "foo", start = 42, end = 60, skipped = 1, kind = elements.kind.start, attrs = "xmlns=\"blah\""),
        actual = elements.next(XML_DOC, 41),
        message = "Second token: foo")
    asserts.equals(env,
        expected = struct(
            label = "bar", start = 90, end = 95, skipped = 30, kind = elements.kind.start, attrs = ""),
        actual = elements.next(XML_DOC, 60),
        message = "Third token: bar")

def greater_than_in_attribute_test(env):
    asserts.equals(env,
        expected = struct(
            label = "qof", start = 109, end = 131, skipped = 3, kind = elements.kind.empty, attrs = "foo=\"blah>foo\""),
        actual = elements.next(XML_DOC, 106),
        message = "Fifth token: qof")

def element_token_array_test(env):
    tokens = elements.token_array(XML_DOC)
    asserts.equals(env, 9, len(tokens))
    asserts.equals(env,
        expected = ["xml", "foo", "bar", "bar", "qof", "blah", "baz", "blah", "foo"],
        actual = [x.label for x in tokens])

# Mostly exercises the parser, but also confirms the root's children.
def parse_test(env):
    root = xml.parse(XML_DOC)
    asserts.equals(env, 2, len(root.children))


TESTS = [
    next_element_basic_test,
    find_element_start_test,
    find_element_end_test,
    finds_xml_header_test,
    skips_comments_test,
    greater_than_in_attribute_test,
    element_token_array_test,
    parse_test,
]

# Roll-up function.
def suite():
    return test_suite("xml utilities", tests = TESTS)
