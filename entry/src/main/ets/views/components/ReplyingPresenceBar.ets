import { User } from '../../models/User';
import { UserAvatar } from './UserAvatar';
import { TypingDots } from './TypingDots';
import { SHADOW_SOFT } from '../../common/theme/Palette';

// 胶囊固定高度：外层(详情页)据此把它与 52vp 悬浮回复按钮垂直居中，故写死并导出。
export const REPLYING_PRESENCE_BAR_HEIGHT: number = 36;

// 详情页底部"正在回复"悬浮条：左侧叠放正在回复者的头像，右侧"正在回复"+三点跳动。
// 仿 Discourse 的 who-is-replying 指示。位置与垂直对齐由外层(详情页)决定，本组件只管内容与样式。
@Component
export struct ReplyingPresenceBar {
  // 正在回复的用户（UI 测试期传假数据）。@Prop：父级数组变化时同步刷新。
  @Prop users: User[] = [];
  private readonly avatarSize: number = 24;
  // 头像左叠量：后一个压在前一个上，形成 Discourse 那种叠放。
  private readonly overlap: number = 9;

  build() {
    Row() {
      Row() {
        // 每个头像统一 -overlap 左移形成叠放；外层补一个 overlap 左内边距抵消第一个，使首个头像齐平。
        // 不按 index 设 margin：keyed ForEach 复用已存在项时不重跑生成器，index 会过期导致位置错乱。
        ForEach(this.users, (user: User) => {
          UserAvatar({ user: user, avatarSize: this.avatarSize })
            .margin({ left: -this.overlap })
        }, (user: User) => user.id.toString())
      }
      .padding({ left: this.overlap })
      .alignItems(VerticalAlign.Center)

      // 文字与三点底部对齐(对齐 Discourse：句号点落在文字基线上，从底部起跳)。
      Row() {
        Text('正在回复')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        // 三点略微离底 2vp，落在文字基线附近而非贴到 descender 底。
        TypingDots()
          .margin({ left: 4, bottom: 2 })
      }
      .alignItems(VerticalAlign.Bottom)
      .margin({ left: 8, right: 6 })
    }
    .height(REPLYING_PRESENCE_BAR_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 6, right: 14 })
    // 玻璃磨砂：与右下角悬浮回复按钮"开启玻璃"完全同一套 backgroundEffect——radius 出磨砂强度、
    // 半透明底色(hds_floating_action_bg 低 alpha)保持通透看得穿身后帖子、saturation 提饱和不发灰。
    // 不用 backgroundBlurStyle(那套磨砂与不透明绑死，越糊越白，做不到强磨砂+通透)。
    .backgroundEffect({
      radius: 28,
      color: $r('app.color.hds_floating_action_bg'),
      saturation: 1.2
    })
    // 胶囊：两端半圆(圆角=半高)。
    .borderRadius(REPLYING_PRESENCE_BAR_HEIGHT / 2)
    .shadow({ radius: 8, color: SHADOW_SOFT, offsetX: 0, offsetY: 2 })
  }
}
