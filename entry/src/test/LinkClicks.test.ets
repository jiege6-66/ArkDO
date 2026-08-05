import { describe, it, expect } from '@ohos/hypium';
import { buildLinkClicks, clicksForHref } from '../main/ets/services/topic/LinkClicks';
import { DiscourseLinkCount } from '../main/ets/services/topic/TopicApiTypes';

// 真实样本(linux.do t/850000 一楼):外链两条,href 与 link_counts.url 逐字相同。
const REAL_COOKED: string =
  '<p>分享一个网盘搜索：<a href="https://so.252035.xyz/" rel="noopener nofollow ugc">https://so.252035.xyz/</a>' +
  '，源码 <a href="https://github.com/fish2018/pansou" class="inline-onebox" rel="noopener nofollow ugc">GitHub</a></p>';

function count(url: string, clicks: number, reflection: boolean = false, internal: boolean = false): DiscourseLinkCount {
  return { url: url, clicks: clicks, reflection: reflection, internal: internal };
}

export default function linkClicksTest() {
  describe('LinkClicks', () => {
    it('maps external links to their click counts', 0, () => {
      const map: Map<string, number> | undefined =
        buildLinkClicks(REAL_COOKED, [count('https://so.252035.xyz/', 477), count('https://github.com/fish2018/pansou', 192)]);
      expect(clicksForHref(map, 'https://so.252035.xyz/')).assertEqual(477);
      expect(clicksForHref(map, 'https://github.com/fish2018/pansou')).assertEqual(192);
    });

    it('returns undefined when there is nothing worth showing', 0, () => {
      expect(buildLinkClicks(REAL_COOKED, undefined) === undefined).assertTrue();
      expect(buildLinkClicks(REAL_COOKED, []) === undefined).assertTrue();
      // 0 次点击不建表:官方也是 clicks < 1 就不挂角标,而不是挂个 0。
      expect(buildLinkClicks(REAL_COOKED, [count('https://so.252035.xyz/', 0)]) === undefined).assertTrue();
    });

    it('drops reflections (other topics linking back to this one)', 0, () => {
      // 反链带着 clicks 一起下发,但它压根不在正文 HTML 里,不该占表位。
      const map: Map<string, number> | undefined =
        buildLinkClicks(REAL_COOKED, [count('https://linux.do/t/topic/999866', 3, true, true)]);
      expect(map === undefined).assertTrue();
    });

    it('drops links that only appear inside a quote card', 0, () => {
      // 引用别人的话里带的链接:点击数记在原帖上,本楼不该再标一遍。
      const cooked: string =
        '<aside class="quote quote-modified" data-post="1" data-topic="780754">' +
        '<blockquote><p>见 <a href="https://example.com/a">这里</a></p></blockquote></aside>' +
        '<p>我也贴一个 <a href="https://example.com/b">b</a></p>';
      const map: Map<string, number> | undefined =
        buildLinkClicks(cooked, [count('https://example.com/a', 12), count('https://example.com/b', 5)]);
      expect(clicksForHref(map, 'https://example.com/a')).assertEqual(0);
      expect(clicksForHref(map, 'https://example.com/b')).assertEqual(5);
    });

    it('keeps onebox links (onebox is also an aside, but it is our own card)', 0, () => {
      const cooked: string =
        '<aside class="onebox githubrepo"><header class="source">' +
        '<a href="https://github.com/fish2018/pansou" target="_blank">github.com</a></header></aside>';
      const map: Map<string, number> | undefined =
        buildLinkClicks(cooked, [count('https://github.com/fish2018/pansou', 192)]);
      expect(clicksForHref(map, 'https://github.com/fish2018/pansou')).assertEqual(192);
    });

    it('resolves relative hrefs the same way the renderer does', 0, () => {
      // 渲染层的 token.href 走过 resolveUrl(相对路径补主站域名),表键必须同形才配得上。
      const cooked: string = '<p><a href="/t/topic/780754">帖子</a></p>';
      const map: Map<string, number> | undefined =
        buildLinkClicks(cooked, [count('https://linux.do/t/topic/780754', 7, false, true)]);
      expect(clicksForHref(map, 'https://linux.do/t/topic/780754')).assertEqual(7);
    });

    it('matches internal links ignoring the query string', 0, () => {
      // 服务端按去掉 query 的地址计数,cooked 里的 href 却可能带 ?u=xxx。
      const cooked: string = '<p><a href="https://linux.do/t/topic/780754?u=someone">帖子</a></p>';
      const map: Map<string, number> | undefined =
        buildLinkClicks(cooked, [count('https://linux.do/t/topic/780754', 7, false, true)]);
      expect(clicksForHref(map, 'https://linux.do/t/topic/780754?u=someone')).assertEqual(7);
    });

    it('matches attachments whose link_counts url is a relative upload path', 0, () => {
      const cooked: string =
        '<p><a class="attachment" href="https://linux.do/uploads/default/original/4X/a/b/c.zip">c.zip</a></p>';
      const map: Map<string, number> | undefined =
        buildLinkClicks(cooked, [count('/uploads/default/original/4X/a/b/c.zip', 33, false, true)]);
      expect(clicksForHref(map, 'https://linux.do/uploads/default/original/4X/a/b/c.zip')).assertEqual(33);
    });

    it('skips category badges and hashtags', 0, () => {
      // 官方 isValidLink 排除这类链接;它们即便被算进 link_counts 也不该显示成"这个链接被点了几次"。
      const cooked: string =
        '<p><a class="hashtag-cooked" href="/c/resource/14">#资源</a>' +
        '<a class="badge-category__wrapper" href="/c/resource/14">资源</a></p>';
      const map: Map<string, number> | undefined =
        buildLinkClicks(cooked, [count('https://linux.do/c/resource/14', 9, false, true)]);
      expect(map === undefined).assertTrue();
    });

    it('clicksForHref is inert without a table', 0, () => {
      expect(clicksForHref(undefined, 'https://example.com/a')).assertEqual(0);
      expect(clicksForHref(new Map<string, number>(), 'https://example.com/a')).assertEqual(0);
    });
  });
}
