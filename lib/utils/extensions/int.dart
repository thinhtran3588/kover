extension IntExtensions on int {
  String prettyInt() {
    if (this >= 1000000000) {
      return '${(this / 1000000000).toStringAsFixed(1)}B';
    } else if (this >= 1000000) {
      return '${(this / 1000000).toStringAsFixed(1)}M';
    } else if (this >= 1000) {
      return '${(this / 1000).toStringAsFixed(1)}K';
    } else {
      return toString();
    }
  }
}

/// Local (on-device) books are opened in the reader with the negated local
/// book id as series and chapter id. Kavita ids are always positive.
extension LocalBookIds on int {
  bool get isLocalBook => this < 0;

  int get localBookId => -this;
}
