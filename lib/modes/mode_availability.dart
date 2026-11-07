import '../content/models.dart';

/// One playable mode: its picker title, grade range and input.
class ModeInfo {
  const ModeInfo({
    required this.mode,
    required this.title,
    required this.minGrade,
    required this.maxGrade,
    required this.usesCamera,
  });

  final ModeKind mode;
  final String title;
  final int minGrade, maxGrade;
  final bool usesCamera;
}

/// Single source of truth for which mode is offered at which grade; shared by
/// the mode picker and `GameController`.
const List<ModeInfo> kModeInfos = [
  ModeInfo(
    mode: ModeKind.laneJump,
    title: 'Nhảy làn',
    minGrade: 1,
    maxGrade: 2,
    usesCamera: true,
  ),
  ModeInfo(
    mode: ModeKind.catchIt,
    title: 'Hứng hình',
    minGrade: 1,
    maxGrade: 2,
    usesCamera: true,
  ),
  ModeInfo(
    mode: ModeKind.memoryFlip,
    title: 'Lật thẻ',
    minGrade: 2,
    maxGrade: 5,
    usesCamera: true,
  ),
  ModeInfo(
    mode: ModeKind.balloonPop,
    title: 'Chọc bóng',
    minGrade: 3,
    maxGrade: 5,
    usesCamera: true,
  ),
  ModeInfo(
    mode: ModeKind.dragSpell,
    title: 'Ghép chữ',
    minGrade: 3,
    maxGrade: 5,
    usesCamera: true,
  ),
  ModeInfo(
    mode: ModeKind.skyShoot,
    title: 'Bắn cung',
    minGrade: 3,
    maxGrade: 5,
    usesCamera: true,
  ),
  ModeInfo(
    mode: ModeKind.sayIt,
    title: 'Nói đi',
    minGrade: 1,
    maxGrade: 5,
    usesCamera: false,
  ),
];

/// Every mode offered at [grade].
Set<ModeKind> modesForGrade(int grade) => {
  for (final i in kModeInfos)
    if (i.minGrade <= grade && grade <= i.maxGrade) i.mode,
};

/// The per-grade mix played by "Chơi": grades 1-2 LaneJump, 3-5 DragSpell
/// and SkyShoot.
Set<ModeKind> defaultModesForGrade(int grade) =>
    grade >= 3 ? {ModeKind.dragSpell, ModeKind.skyShoot} : {ModeKind.laneJump};
