import { TopicCategory } from '../../models/Topic';
import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';
import { getCategoryColor, getCategoryIcon, getCategoryLogo, resolveBadgeAssetUrl } from './TopicBadgeUtils';

const CATEGORY_ICON_SIZE: number = 10;
const CATEGORY_LOGO_SIZE: number = 10;
const RESTRICTED_CATEGORY_ICON_SIZE: number = 10;
const CATEGORY_COLOR_DOT_SIZE: number = 10;

@Component
export struct TopicCategoryBadge {
  category: TopicCategory = {
    id: 0,
    name: '',
    color: '6B7280',
    textColor: 'FFFFFF'
  };
  parentCategory?: TopicCategory;
  // 点徽章按该分类筛选。默认关:多数场景(详情页头、书签/搜索等列表)徽章只是展示,
  // 点击应当照旧穿透到整行去打开帖子。
  @Prop tappable: boolean = false;
  onTap: () => void = () => {};

  @State private pressed: boolean = false;

  build() {
    Row() {
      if (this.getIcon()) {
        FaIconView({
          icon: this.getIcon() as FaIconDefinition,
          color: getCategoryColor(this.category),
          iconSize: CATEGORY_ICON_SIZE
        })
          .margin({ right: 3 })
      } else if (this.getLogoUrl().length > 0) {
        Image(resolveBadgeAssetUrl(this.getLogoUrl()))
          .width(CATEGORY_LOGO_SIZE)
          .height(CATEGORY_LOGO_SIZE)
          .objectFit(ImageFit.Contain)
          .margin({ right: 3 })
      } else if (this.category.readRestricted && this.getLockIcon()) {
        FaIconView({
          icon: this.getLockIcon() as FaIconDefinition,
          color: getCategoryColor(this.category),
          iconSize: RESTRICTED_CATEGORY_ICON_SIZE
        })
          .margin({ right: 3 })
      } else {
        Circle()
          .width(CATEGORY_COLOR_DOT_SIZE)
          .height(CATEGORY_COLOR_DOT_SIZE)
          .fill(getCategoryColor(this.category))
          .margin({ right: 5 })
      }

      Text(this.category.name)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .fontWeight(FontWeight.Regular)
    }
    .height(18)
    .alignItems(VerticalAlign.Center)
    .margin({ right: 8 })
    .opacity(this.tappable && this.pressed ? 0.6 : 1)
    // 不可点时整个徽章不参与命中测试,触摸原样落到外层整行(即「点这里也是打开帖子」)。
    // 少了这一句,下面那个 onClick 会把点击吃掉,所有只是展示分类的页面都会变成点徽章毫无反应。
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
    return getCategoryIcon(this.category, this.parentCategory);
  }

  private getLockIcon(): FaIconDefinition | undefined {
    return getFaIcon('lock');
  }

  private getLogoUrl(): string {
    return getCategoryLogo(this.category, this.parentCategory);
  }
}
