import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';

const CARD_RADIUS: number = 8;
const HEADER_ICON_SIZE: number = 14;
const LINK_ICON_SIZE: number = 11;

// 抽奖帖提醒卡:详情页摘要(标题/标签/统计)下方、一楼正文上方的一张琥珀色卡片。
//
// 它是 List 首个 ListItem 的内容之一,跟着列表滚走,不做常驻悬浮 —— 详情页底部已经挤了
// 「N 条新回复」「正在回复」「悬浮回复按钮」三层浮层,顶部是 HDS 沉浸式标题栏覆盖层,
// 再插一条常驻横幅只会打架;而这条提醒看一眼就够了,滚走是它应有的归宿。
//
// 每进一个抽奖帖都是展开态,不记「看过了」:被提醒挡下的是永久禁言这种不可逆后果,
// 记忆一次就沉默的代价不对称。收起只在本次浏览有效(组件卸载即复位),
// 想彻底不看走设置页-实验性功能里的总开关。
@Component
export struct LotteryNoticeCard {
  // 点「查看官方公告」:上抛给页面走站内链接路由,直开原生详情页(不落 WebView)。
  onOpenAnnouncement: () => void = () => {};

  @State private collapsed: boolean = false;

  build() {
    // 外层只负责左右留白:左右 10 与摘要卡、楼层正文的横向内边距对齐,视觉上是同一列。
    // 边距走 padding 而不是给卡片加 margin —— 卡片是 width('100%'),margin 不计入这个
    // 百分比,会把卡片撑到与父容器同宽再往外挤,左右间距等于没加。
    Column() {
      Column() {
        // 标题行整行可点:展开态点它收起,收起态点它展开。收起后标题本身就换成一句提示,
        // 让这一行在两种状态下都有信息量,而不是一个空壳把手。
        Row() {
          FaIconView({
            icon: this.faIcon('gift'),
            color: $r('app.color.warning'),
            iconSize: HEADER_ICON_SIZE
          })
            .margin({ right: 8 })

          Text(this.collapsed ? '抽奖帖 · 回复请说明你为什么需要这个奖品' : '抽奖帖提醒')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.warning'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          FaIconView({
            icon: this.faIcon(this.collapsed ? 'angle-down' : 'angle-up'),
            color: $r('app.color.warning'),
            iconSize: HEADER_ICON_SIZE
          })
            .margin({ left: 8 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
            this.collapsed = !this.collapsed;
          });
        })

        if (!this.collapsed) {
          Column() {
            Text('回复被举报后会被删除并永久禁言的三种情况：')
              .fontSize(13)
              .fontColor($r('app.color.text_body'))
              .width('100%')
              .margin({ top: 10 })

            this.Bullet('纯凑字数（符号、单字、英文占位）')
            this.Bullet('复读或复制别人的回复')
            this.Bullet('与奖品无关的内容')

            Text('永久禁言后仍可登录浏览、私信，但不能再回复、发帖和参与抽奖。如有异议可私信管理申诉。')
              .fontSize(13)
              .lineHeight(20)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .margin({ top: 10 })

            Text('官方建议：非必要不参与抽奖。确实需要，就说说你为什么需要它。')
              .fontSize(13)
              .lineHeight(20)
              .fontColor($r('app.color.text_body'))
              .width('100%')
              .margin({ top: 6 })

            // 「查看官方公告」做成一行文字链而非按钮:这张卡的主角是那三条红线,
            // 加个实心按钮会把视觉重心抢到跳转上。
            Row() {
              Text('查看官方公告')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ld_accent'))

              FaIconView({
                icon: this.faIcon('arrow-right'),
                color: $r('app.color.ld_accent'),
                iconSize: LINK_ICON_SIZE
              })
                .margin({ left: 5 })
            }
            .alignItems(VerticalAlign.Center)
            .margin({ top: 12 })
            .onClick(() => {
              this.onOpenAnnouncement();
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 12, right: 12, top: 10, bottom: 12 })
      .backgroundColor($r('app.color.lottery_notice_bg'))
      .border({ width: 1, color: $r('app.color.lottery_notice_border') })
      .borderRadius(CARD_RADIUS)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 12, bottom: 4 })
  }

  @Builder
  private Bullet(text: string) {
    Row() {
      Text('·')
        .fontSize(13)
        .lineHeight(20)
        .fontColor($r('app.color.text_secondary'))
        .margin({ left: 2, right: 8 })

      Text(text)
        .fontSize(13)
        .lineHeight(20)
        .fontColor($r('app.color.text_body'))
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: 4 })
  }

  // 图标资源未载入时退化成空路径(FaIconView 自身容错),不让缺图把整张卡拖垮。
  private faIcon(name: string): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon(name);
    return def ? def : { id: name, rawfilePath: '' };
  }
}
