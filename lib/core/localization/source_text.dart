import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// A search/display projection only. Provider records remain byte-for-byte intact.
String plainSourceText(String markup) {
  final output = StringBuffer();
  void visit(dom.Node node) {
    if (node is dom.Text) {
      output.write(node.data);
      return;
    }
    if (node is dom.Element &&
        ['script', 'style', 'img', 'iframe'].contains(node.localName)) {
      return;
    }
    for (final child in node.nodes) {
      visit(child);
    }
    if (node is dom.Element &&
        ['br', 'p', 'div', 'li'].contains(node.localName)) {
      output.write(' ');
    }
  }

  visit(html.parseFragment(markup));
  return output.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

String normalizeMeaningSearch(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
