import { describe, it, expect } from '@ohos/hypium';
import {
  getEmojiGroups,
  getEmojiNameByUrl,
  getEmojiUrl,
  loadEmojiUrlsFromJson
} from '../main/ets/views/components/EmojiUrlRegistry';

export default function emojiCatalogTest() {
  describe('emojiCatalogTest', () => {
    it('keepsGroupsAndResolvedUrls', 0, () => {
      const count: number = loadEmojiUrlsFromJson(
        '{"faces":[{"name":"heart","url":"/images/emoji/heart.png","tonable":false}],' +
        '"custom":[{"name":"bili_001","url":"//cdn.example/bili.png","created_by":"system"}]}'
      );

      expect(count).assertEqual(2);
      expect(getEmojiGroups().length).assertEqual(2);
      expect(getEmojiGroups()[0].key).assertEqual('faces');
      expect(getEmojiGroups()[1].items[0].createdBy).assertEqual('system');
      expect(getEmojiUrl('bili_001')).assertEqual('https://cdn.example/bili.png');
      expect(getEmojiNameByUrl('https://cdn.example/bili.png')).assertEqual('bili_001');
    });

    it('rejectsMalformedCatalog', 0, () => {
      expect(loadEmojiUrlsFromJson('{bad json')).assertEqual(0);
      expect(getEmojiGroups().length).assertEqual(0);
      expect(loadEmojiUrlsFromJson('null')).assertEqual(0);
    });
  });
}
