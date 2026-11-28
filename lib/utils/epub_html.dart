import 'package:html/dom.dart';

/// Replaces the SVG `<image>` node [imageNode] with an `<img>` showing
/// [dataUri]. When the image is the child of an `<svg>`, the whole `<svg>` is
/// replaced by a `<div>` that keeps its class and style.
void replaceSvgImage(Element imageNode, String dataUri) {
  final imgTag = Element.tag('img');
  imgTag.attributes['src'] = dataUri;

  // Copy over width/height if present
  if (imageNode.attributes['width'] != null) {
    imgTag.attributes['width'] = imageNode.attributes['width']!;
  }
  if (imageNode.attributes['height'] != null) {
    imgTag.attributes['height'] = imageNode.attributes['height']!;
  }
  if (imageNode.attributes.containsKey('style')) {
    imgTag.attributes['style'] = imageNode.attributes['style']!;
  }
  if (imageNode.attributes.containsKey('class')) {
    imgTag.attributes['class'] = imageNode.attributes['class']!;
  }

  final svgParent = imageNode.parent;
  if (svgParent != null && svgParent.localName == 'svg') {
    final newParent = Element.tag('div');

    if (svgParent.attributes.containsKey('class')) {
      newParent.attributes['class'] = svgParent.attributes['class']!;
    }
    if (svgParent.attributes.containsKey('style')) {
      newParent.attributes['style'] = svgParent.attributes['style']!;
    }
    newParent.append(imgTag);
    svgParent.replaceWith(newParent);
  } else {
    imageNode.replaceWith(imgTag);
  }
}
