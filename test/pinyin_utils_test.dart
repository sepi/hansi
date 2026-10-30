import 'package:flutter_test/flutter_test.dart';
import 'package:hansi/pinyin_utils.dart';

void main() {
  test('toNumberedPinyin puts each tone after its own syllable', () {
    const cases = {
      'nǐ': 'ni3',
      'hǎo': 'hao3',
      'nǐ hǎo': 'ni3 hao3',
      'nǐhǎo': 'ni3hao3',
      'kěnéng': 'ke3neng2',
      'zhōngguó': 'zhong1guo2',
      'pīnyīn': 'pin1yin1',
      'lǜsè': 'lü4se4',
      "nǚ'ér": "nü3'er2",
      'Běijīng': 'Bei3jing1',
      'xiǎng': 'xiang3',
      'nàr': 'nar4',
      "tiān'ānmén": "tian1'an1men2",
      'shēngrì': 'sheng1ri4',
      'yīnyuè': 'yin1yue4',
      'ni3': 'ni3',
      'nihao': 'nihao',
    };
    cases.forEach((input, want) {
      expect(toNumberedPinyin(input), want, reason: input);
    });
  });
}
