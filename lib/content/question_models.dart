import '../input/action_detector.dart';
import 'models.dart';

enum QuestionForm {
  listenPickPicture,
  seePicturePickWord,
  listenPickWord,
  fillBlank,
  spellWord,
  orderSentence,
  memoryMatch,
  popWord,
  trueFalse,
  doAction,
}

class ChoiceOption {
  const ChoiceOption({
    required this.itemId,
    required this.showPicture,
    required this.showWord,
  });

  final String itemId;
  final bool showPicture, showWord;
}

sealed class Question {
  const Question();
  String get itemId;
  String get ttsText;
  QuestionForm get form;
}

class ChoiceQuestion extends Question {
  const ChoiceQuestion({
    required this.itemId,
    required this.form,
    required this.ttsText,
    this.promptText,
    this.promptImageItemId,
    required this.choices,
    required this.correctIndex,
  });

  @override
  final String itemId;
  @override
  final QuestionForm form;
  @override
  final String ttsText;
  final String? promptText, promptImageItemId;
  final List<ChoiceOption> choices;
  final int correctIndex;
}

class SpellQuestion extends Question {
  const SpellQuestion({
    required this.itemId,
    required this.ttsText,
    required this.word,
    required this.tiles,
    this.imageItemId,
  });

  @override
  final String itemId;
  @override
  final String ttsText;
  final String word;
  final List<String> tiles;
  final String? imageItemId;

  @override
  QuestionForm get form => QuestionForm.spellWord;
}

class OrderQuestion extends Question {
  const OrderQuestion({
    required this.itemId,
    required this.ttsText,
    required this.words,
    required this.answer,
  });

  @override
  final String itemId;
  @override
  final String ttsText;

  /// Shuffled words (never equal to [answer]).
  final List<String> words, answer;

  @override
  QuestionForm get form => QuestionForm.orderSentence;
}

/// puppySays: the puppy names a body [action]. [itemId] is the action id (not
/// a content item), [ttsText] the spoken command, [command] the text shown and
/// [hintVi] the Vietnamese hint.
class ActionQuestion extends Question {
  const ActionQuestion({
    required this.itemId,
    required this.ttsText,
    required this.command,
    required this.hintVi,
    required this.action,
  });

  @override
  final String itemId;
  @override
  final String ttsText;
  final String command, hintVi;
  final PuppyAction action;

  @override
  QuestionForm get form => QuestionForm.doAction;
}

class PlannedQuestion {
  const PlannedQuestion({required this.mode, required this.question});

  final ModeKind mode;
  final Question question;
}
