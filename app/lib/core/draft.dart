/// A proposal may only replace exactly the revision from which it was made.
/// This guard is shared by OCR, dictation and asynchronous calculation.
class RevisionedDraft {
  String latex = '';
  int revision = 0;
  void edit(String value) {
    latex = value;
    revision++;
  }

  bool accept(String value, int baseRevision) {
    if (baseRevision != revision) return false;
    edit(value);
    return true;
  }
}
