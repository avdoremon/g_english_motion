/// Vietnamese voice lines. Each has a recorded clip (when present) and a
/// caption that is always shown.
enum VoiceLine {
  welcome('Chào mừng em! Hãy đứng trước camera nhé'),
  standStill('Đứng yên một chút nhé'),
  stepBack('Lùi ra xa hơn một chút'),
  correct1('Giỏi quá!'),
  correct2('Đúng rồi, tuyệt vời!'),
  correct3('Chính xác! Em làm tốt lắm!'),
  tryAgain('Chưa đúng rồi, thử lại nhé!'),

  /// A round that ran out of time: neutral on purpose. The child may simply
  /// not have been seen jumping, so nothing here says they were wrong.
  outOfTime('Hết giờ rồi, câu sau nhé!'),
  theAnswerIs('Đáp án đúng là'),
  jumpToChoose('Đứng vào làn em chọn rồi nhảy lên nhé'),
  raiseHandsToChoose('Giơ hai tay lên để chọn'),
  pullTheRope('Kéo dây thật mạnh nào!'),
  sayTheWord('Hãy đọc to từ này'),
  levelComplete('Giỏi lắm! Hoàn thành rồi!'),
  takeABreak('Nghỉ một chút nhé!');

  const VoiceLine(this.caption);

  final String caption;

  /// Whether [text] is the caption of a Vietnamese voice line (as opposed to
  /// an English word that is being spoken).
  static bool isCaption(String text) => values.any((l) => l.caption == text);

  String get assetPath => 'assets/audio/vi/$name.m4a';
}
