"""Run with: python3 -m unittest discover -s test/tools -p 'test_*.py'"""
import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'tools'))
import tag_modes  # noqa: E402


def item(id_, word, image='x.png', distractors=('a', 'b'), modes=('sayIt',)):
    return {
        'id': id_,
        'word': word,
        'ttsText': word,
        'image': image,
        'syllables': 1,
        'sentencePatterns': [],
        'distractorIds': list(distractors),
        'spokenVariants': [],
        'modes': list(modes),
    }


def unit(grade, items):
    return {'grade': grade, 'unit': 'u01', 'index': 1, 'title': 't', 'items': items}


class TagModesTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root)

    def write(self, name, data):
        d = os.path.join(self.root, os.path.dirname(name))
        os.makedirs(d, exist_ok=True)
        p = os.path.join(self.root, name)
        with open(p, 'w', encoding='utf-8') as f:
            f.write(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
        return p

    def read(self, name):
        with open(os.path.join(self.root, name), encoding='utf-8') as f:
            return f.read()

    def fixture(self):
        self.write('grade3/u01.json', unit(3, [
            item('g3u01-cat', 'cat', distractors=('g3u01-cap', 'g3u01-cut')),
            item('g3u01-cap', 'cap', distractors=('g3u01-cat', 'g3u01-cut')),
            item('g3u01-cut', 'Cut', distractors=('g3u01-cat', 'g3u01-cap')),
            item('g3u01-elephant', 'elephant', distractors=('g3u01-cat', 'g3u01-cap')),
            item('g3u01-noimg', 'bat', image=None,
                 distractors=('g3u01-cat', 'g3u01-cap')),
            item('g3u01-fewd', 'cot', distractors=('g3u01-cat',)),
        ]))

    def modes(self, name, id_):
        data = json.loads(self.read(name))
        return next(i['modes'] for i in data['items'] if i['id'] == id_)

    def test_lev(self):
        self.assertEqual(tag_modes.lev('cat', 'cap'), 1)
        self.assertEqual(tag_modes.lev('', 'abc'), 3)
        self.assertEqual(tag_modes.lev('kitten', 'sitting'), 3)
        self.assertEqual(tag_modes.lev('same', 'same'), 0)

    def test_lev_parity(self):
        # Keep in step with question_generator_modes_test.dart.
        sample = [('cat', 'cap', 1), ('', 'abc', 3), ('kitten', 'sitting', 3),
                  ('flaw', 'lawn', 2), ('intention', 'execution', 5),
                  ('same', 'same', 0), ('book', 'back', 2)]
        for a, b, d in sample:
            self.assertEqual(tag_modes.lev(a, b), d, (a, b))
            self.assertEqual(tag_modes.lev(b, a), d, (b, a))

    def test_check_exit_2_on_non_canonical_file(self):
        p = os.path.join(self.root, 'grade3', 'u01.json')
        os.makedirs(os.path.dirname(p))
        with open(p, 'w', encoding='utf-8') as f:
            json.dump(unit(3, [item('g3u01-cat', 'cat')]), f, indent=4)
        before = self.read('grade3/u01.json')
        self.assertEqual(tag_modes.run(self.root, check=True), 2)
        self.assertEqual(tag_modes.run(self.root, check=False), 2)
        self.assertEqual(self.read('grade3/u01.json'), before)

    def test_idempotent(self):
        self.fixture()
        self.assertEqual(tag_modes.run(self.root, check=False), 0)
        first = self.read('grade3/u01.json')
        self.assertEqual(tag_modes.run(self.root, check=False), 0)
        self.assertEqual(self.read('grade3/u01.json'), first)
        self.assertEqual(tag_modes.run(self.root, check=True), 0)

    def test_check_fails_when_write_needed_and_does_not_write(self):
        self.fixture()
        before = self.read('grade3/u01.json')
        self.assertEqual(tag_modes.run(self.root, check=True), 1)
        self.assertEqual(self.read('grade3/u01.json'), before)

    def test_no_image_no_memory_flip(self):
        self.fixture()
        tag_modes.run(self.root, check=False)
        m = self.modes('grade3/u01.json', 'g3u01-noimg')
        self.assertNotIn('memoryFlip', m)
        self.assertNotIn('catchIt', m)
        self.assertNotIn('balloonPop', m)

    def test_needs_two_valid_distractors(self):
        self.fixture()
        tag_modes.run(self.root, check=False)
        m = self.modes('grade3/u01.json', 'g3u01-fewd')
        self.assertNotIn('memoryFlip', m)
        self.assertNotIn('catchIt', m)

    def test_yes_no_needs_image_and_one_valid_distractor(self):
        self.fixture()
        self.write('grade3/u02.json', unit(3, [
            item('g3u02-self', 'owl', distractors=('g3u02-self',)),
            item('g3u02-ghost', 'fox', distractors=('nope',)),
            item('g3u02-one', 'ant', distractors=('nope', 'g3u01-cat')),
        ]))
        tag_modes.run(self.root, check=False)
        m = self.modes('grade3/u01.json', 'g3u01-fewd')
        self.assertIn('yesNo', m)  # one valid distractor is enough
        self.assertNotIn('memoryFlip', m)
        self.assertNotIn('yesNo', self.modes('grade3/u01.json', 'g3u01-noimg'))
        self.assertNotIn('yesNo', self.modes('grade3/u02.json', 'g3u02-self'))
        self.assertNotIn('yesNo', self.modes('grade3/u02.json', 'g3u02-ghost'))
        self.assertIn('yesNo', self.modes('grade3/u02.json', 'g3u02-one'))

    def test_yes_no_never_removed(self):
        self.fixture()
        data = json.loads(self.read('grade3/u01.json'))
        data['items'][4]['modes'].append('yesNo')  # no image: not earned
        self.write('grade3/u01.json', data)
        tag_modes.run(self.root, check=False)
        self.assertIn('yesNo', self.modes('grade3/u01.json', 'g3u01-noimg'))

    def test_balloon_pop_needs_two_near_words_case_insensitive(self):
        self.fixture()
        tag_modes.run(self.root, check=False)
        # cat: cap (1) and Cut (1) are near.
        self.assertIn('balloonPop', self.modes('grade3/u01.json', 'g3u01-cat'))
        self.assertNotIn('balloonPop', self.modes('grade3/u01.json', 'g3u01-elephant'))

    def test_balloon_pop_pool_is_per_grade(self):
        self.write('grade3/u01.json', unit(3, [
            item('g3u01-cat', 'cat', distractors=('g3u01-cap', 'g3u01-cut')),
            item('g3u01-cap', 'cap', distractors=('g3u01-cat', 'g3u01-cut')),
        ]))
        self.write('grade4/u01.json', unit(4, [
            item('g4u01-cut', 'cut', distractors=('g3u01-cat', 'g3u01-cap')),
        ]))
        tag_modes.run(self.root, check=False)
        self.assertNotIn('balloonPop', self.modes('grade3/u01.json', 'g3u01-cat'))

    def test_additive_and_preserves_order_and_existing_tags(self):
        self.fixture()
        tag_modes.run(self.root, check=False)
        m = self.modes('grade3/u01.json', 'g3u01-cat')
        self.assertEqual(m[0], 'sayIt')
        self.assertEqual(m, ['sayIt', 'memoryFlip', 'catchIt', 'balloonPop', 'yesNo'])
        # A manually authored tag is never removed, even if no longer earned.
        data = json.loads(self.read('grade3/u01.json'))
        data['items'][3]['modes'].append('balloonPop')
        self.write('grade3/u01.json', data)
        tag_modes.run(self.root, check=False)
        self.assertIn('balloonPop', self.modes('grade3/u01.json', 'g3u01-elephant'))

    def test_only_modes_arrays_change_and_key_order_kept(self):
        self.fixture()
        before = json.loads(self.read('grade3/u01.json'))
        tag_modes.run(self.root, check=False)
        after = json.loads(self.read('grade3/u01.json'))
        for b, a in zip(before['items'], after['items']):
            self.assertEqual(list(b.keys()), list(a.keys()))
            b2 = dict(b, modes=None)
            a2 = dict(a, modes=None)
            self.assertEqual(b2, a2)
            self.assertEqual(a['modes'][:len(b['modes'])], b['modes'])


if __name__ == '__main__':
    unittest.main()
