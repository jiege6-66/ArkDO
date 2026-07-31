import { TopicTag } from '../../models/Topic';
import { FaIconDefinition, FaIconView } from './FaIcon';
import { getTagColor, getTagIcon } from './TopicBadgeUtils';

const TAG_ICON_SIZE: number = 10;

@Component
export struct TopicTagBadge {
  tag: TopicTag = {
    name: ''
  };
  // 点徽章按该标签筛选。默认空实现:多数场景(详情页头、个人主页列表)不接这条线,
  // 此时徽章仍是纯展示,点击照旧落到外层整行的点击上。
  onTap: () => void = () => {};
  // 可点时给按下反馈,不可点时保持静止——手感本身就是「这里能不能点」的提示。
  // @Prop:开关是运行时能翻转的,普通成员变量只在创建时赋值一次,同步不进来。
  @Prop tappable: boolean = false;

  @State private pressed: boolean = false;

  build() {
    Row() {
      if (this.getIcon()) {
        FaIconView({
          icon: this.getIcon() as FaIconDefinition,
          color: getTagColor(this.tag.name),
          iconSize: TAG_ICON_SIZE
        })
          .margin({ right: 4 })
      }

      Text(this.tag.name)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .fontWeight(FontWeight.Regular)
    }
    .height(20)
    .padding({ left: 4, right: 4 })
    .backgroundColor($r('app.color.surface_muted'))
    .borderRadius(2)
    .alignItems(VerticalAlign.Center)
    .margin({ right: 7 })
    .opacity(this.tappable && this.pressed ? 0.6 : 1)
    // 不可点时整个徽章不参与命中测试,触摸原样落到外层整行(即「点这里也是打开帖子」)。
    // 少了这一句,下面那个 onClick 会把点击吃掉,所有只是展示标签的页面都会变成点标签毫无反应。
    .hitTestBehavior(this.tappable ? HitTestMode.Default : HitTestMode.None)
    .onTouch((event: TouchEvent) => {
      if (!this.tappable) {
        return;
      }
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      if (this.tappable) {
        this.onTap();
      }
    })
  }

  private getIcon(): FaIconDefinition | undefined {
    return getTagIcon(this.tag.name);
  }
}
