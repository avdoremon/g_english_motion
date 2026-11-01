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
  theAnswerIs('Đáp án đúng là'),
  jumpToChoose('Đứng vào làn em chọn rồi nhảy lên nhé'),
  raiseHandsToChoose('Giơ hai tay lên để chọn'),
  pullTheRope('Kéo dây thật mạnh nào!'),
  sayTheWord('Hãy đọc to từ này'),
  levelComplete('Giỏi lắm! Hoàn thành rồi!'),
  takeABreak('Nghỉ một chút nhé!');

  const VoiceLine(this.caption);

  final String caption;

  String get assetPath => 'assets/audio/vi/$name.m4a';
}
