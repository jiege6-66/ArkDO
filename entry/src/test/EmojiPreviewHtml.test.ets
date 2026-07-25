import { describe, it, expect } from '@ohos/hypium';
import { EmojiPreviewHtml } from '../main/ets/services/content/EmojiPreviewHtml';

function resolveTestEmoji(name: string): string | undefined {
  if (name === 'heart') {
    return 'https://cdn.example/heart.png';
  }
  if (name === 'piñata') {
    return 'https://cdn.example/pinata.png';
  }
  return undefined;
}

export default function emojiPreviewHtmlTest() {
  describe('emojiPreviewHtmlTest', () => {
    it('rendersKnownShortcodeAsInlineEmojiImage', 0, () => {
      const html: string = EmojiPreviewHtml.render('<p>谢谢 :heart:</p>', resolveTestEmoji);
      expect(html).assertEqual(
        '<p>谢谢 <img class="emoji" src="https://cdn.example/heart.png" alt=":heart:" title=":heart:" width="20" height="20"></p>'
      );
    });

    it('keepsUnknownShortcodeAndRendersFollowingKnownOne', 0, () => {
      const html: string = EmojiPreviewHtml.render('<p>:unknown::heart:</p>', resolveTestEmoji);
      expect(html).assertEqual(
        '<p>:unknown:<img class="emoji" src="https://cdn.example/heart.png" alt=":heart:" title=":heart:" width="20" height="20"></p>'
      );
    });

    it('doesNotRenderInsideInlineOrFencedCode', 0, () => {
      const source: string = '<p><code>:heart:</code></p><pre><code>:heart:</code></pre>';
      expect(EmojiPreviewHtml.render(source, resolveTestEmoji)).assertEqual(source);
    });

    it('doesNotChangeTagAttributesButRendersVisibleLinkText', 0, () => {
      const html: string = EmojiPreviewHtml.render('<a href="/:heart:">:heart:</a>', resolveTestEmoji);
      expect(html).assertEqual(
        '<a href="/:heart:"><img class="emoji" src="https://cdn.example/heart.png" alt=":heart:" title=":heart:" width="20" height="20"></a>'
      );
    });

    it('supportsUnicodeShortcodeNames', 0, () => {
      const html: string = EmojiPreviewHtml.render('<p>:piñata:</p>', resolveTestEmoji);
      expect(html).assertEqual(
        '<p><img class="emoji" src="https://cdn.example/pinata.png" alt=":piñata:" title=":piñata:" width="20" height="20"></p>'
      );
    });
  });
}
