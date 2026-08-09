import resourceManager from '@ohos.resourceManager';
import { common } from '@kit.AbilityKit';
import {
  EmojiGroup,
  EmojiItem,
  getEmojiGroups
} from './EmojiUrlRegistry';

const EMOJI_COLUMNS: string = 'repeat(7, 1fr)';

class EmojiPickerDataSource implements IDataSource {
  private items: EmojiItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): EmojiItem {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  reset(items: EmojiItem[]): void {
    this.items = items.slice();
    for (let index: number = 0; index < this.listeners.length; index++) {
      this.listeners[index].onDataReloaded();
    }
  }
}

@Component
export struct EmojiPicker {
  onSelect: (emoji: EmojiItem) => void = (emoji: EmojiItem) => {};
  onDelete: () => void = () => {};
  @State private groups: EmojiGroup[] = [];
  @State private selectedGroupIndex: number = 0;
  private dataSource: EmojiPickerDataSource = new EmojiPickerDataSource();

  aboutToAppear(): void {
    // 表情表由 EmojiCatalogService 按站点异步拉取并缓存,这里只读已加载的结果 ——
    // 还没拉到就是空分组(选择器显示为空),不再从 rawfile 兜底。
    this.groups = getEmojiGroups();
    if (this.selectedGroupIndex >= this.groups.length) {
      this.selectedGroupIndex = 0;
    }
    if (this.groups.length > 0) {
      this.dataSource.reset(this.groups[this.selectedGroupIndex].items);
    }
  }

  private groupLabel(key: string): string {
    switch (key) {
      case 'smileys_&_emotion': return '笑脸';
      case 'people_&_body': return '人物';
      case 'animals_&_nature': return '自然';
      case 'food_&_drink': return '食物';
      case 'travel_&_places': return '旅行';
      case 'activities': return '活动';
      case 'objects': return '物品';
      case 'symbols': return '符号';
      case 'flags': return '旗帜';
      default: return key;
    }
  }

  build() {
    Column() {
      Row() {
        Scroll() {
          Row({ space: 4 }) {
            ForEach(this.groups, (group: EmojiGroup, index: number) => {
              Button(this.groupLabel(group.key), { type: ButtonType.Normal, stateEffect: true })
                .height(34)
                .padding({ left: 12, right: 12 })
                .fontSize(13)
                .fontColor(index === this.selectedGroupIndex ? $r('app.color.ld_accent') : $r('app.color.text_secondary'))
                .backgroundColor(index === this.selectedGroupIndex ? $r('app.color.immersive_input_field_bg') : Color.Transparent)
                .borderRadius(6)
                .focusable(false)
                .onClick(() => {
                  this.selectedGroupIndex = index;
                  this.dataSource.reset(group.items);
                })
            }, (group: EmojiGroup) => group.key)
          }
          .height(42)
          .padding({ left: 8, right: 4, top: 4, bottom: 4 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .height(42)

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Text('⌫')
            .fontSize(22)
            .fontColor($r('app.color.icon_secondary'))
        }
        .width(44)
        .height(42)
        .backgroundColor(Color.Transparent)
        .borderRadius(6)
        .focusable(false)
        .accessibilityText('删除')
        .onClick(() => {
          this.onDelete();
        })
      }
      .width('100%')
      .height(42)

      Divider()
        .strokeWidth(0.5)
        .color($r('app.color.border'))

      Grid() {
        LazyForEach(this.dataSource, (emoji: EmojiItem) => {
          GridItem() {
            Button({ type: ButtonType.Normal, stateEffect: true }) {
              Image(emoji.url)
                .width(30)
                .height(30)
                .objectFit(ImageFit.Contain)
                .draggable(false)
            }
            .width('100%')
            .height(44)
            .padding(4)
            .backgroundColor(Color.Transparent)
            .borderRadius(6)
            .focusable(false)
            .accessibilityText(`:${emoji.name}:`)
            .onClick(() => {
              this.onSelect(emoji);
            })
          }
        }, (emoji: EmojiItem) => `${emoji.groupKey}-${emoji.name}`)
      }
      .columnsTemplate(EMOJI_COLUMNS)
      .columnsGap(2)
      .rowsGap(2)
      .padding({ left: 8, right: 8, top: 6, bottom: 8 })
      .scrollBar(BarState.Auto)
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.topic_detail_page_bg'))
  }
}
