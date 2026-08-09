import { CurrentSite } from '../../services/site/CurrentSite';
import { FORUM_SUGGESTIONS, ForumDef, ForumPrefs, ForumSuggestion, ForumUpdateResult } from '../../services/site/ForumPrefs';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { Log } from '../../services/logging/Log';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { CARD_GAP, CARD_PADDING, CARD_RADIUS, PAGE_MARGIN } from '../../common/theme/Metrics';
import { SiteUrl } from '../../services/site/SiteUrl';
import { immersiveTitleBarContentTopSpacer } from '../../common/ui/ImmersiveTitleBarLayout';
import {
  ImmersiveLightArea,
  requiresHdsComponentSafeArea,
  requiresHdsLayoutSafeAreaAvoidance
} from '../../common/ui/ImmersiveLightMaterial';
import { buildImmersiveTitleBarStyle } from '../../common/ui/ImmersiveTitleBarStyle';
import { showToast as promptToast } from '../../common/utils/Toast';
import { common } from '@kit.AbilityKit';

const LOG_TAG: string = '[ArkDO][Forums]';

// 添加 / 编辑论坛弹窗。名称可留空(取域名);地址裸域名自动补 https://。
// 编辑态多一枚删除入口 —— 底部只有取消/保存两枚按钮,删除塞不进去,放内容区末尾。
// (与 SitesPage 的站点编辑弹窗同款布局。)
@CustomDialog
struct ForumEditDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: ForumEditDialog({}) });
  isEdit: boolean = false;
  initialName: string = '';
  initialUrl: string = '';
  onConfirm: (name: string, url: string) => void = () => {};
  // 删除:先关弹窗再由页面弹二次确认(两层弹窗叠加在鸿蒙上会打架)。
  onDelete: () => void = () => {};
  @State private name: string = '';
  @State private url: string = '';

  aboutToAppear(): void {
    this.name = this.initialName;
    this.url = this.initialUrl;
  }

  build() {
    Column() {
      Text(this.isEdit ? '编辑论坛' : '添加论坛')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 22, bottom: 18 })

      Column() {
        TextInput({ placeholder: '名称(可留空,默认取域名)', text: this.name })
          .fontSize(15)
          .height(44)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius(12)
          .onChange((value: string) => {
            this.name = value;
          })

        TextInput({ placeholder: '论坛地址,如 meta.discourse.org', text: this.url })
          .fontSize(15)
          .height(44)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius(12)
          .margin({ top: 12 })
          .onChange((value: string) => {
            this.url = value;
          })

        Text('必须是基于 Discourse(开源论坛程序)搭建的站点。')
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .margin({ top: 10 })

        if (this.isEdit) {
          Text('删除论坛')
            .fontSize(15)
            .fontColor($r('app.color.ld_danger'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 18 })
            .onClick(() => {
              this.controller.close();
              this.onDelete();
            })
        }
      }
      .width('100%')
      .padding({ left: 24, right: 24 })
      .margin({ bottom: 20 })

      Divider()
        .strokeWidth(0.5)
        .color($r('app.color.border'))

      Row() {
        Button('取消')
          .type(ButtonType.Normal)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.text_secondary'))
          .fontSize(16)
          .layoutWeight(1)
          .height(52)
          .onClick(() => {
            this.controller.close();
          })

        Divider()
          .vertical(true)
          .strokeWidth(0.5)
          .color($r('app.color.border'))
          .height(24)

        Button(this.isEdit ? '保存' : '添加')
          .type(ButtonType.Normal)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.ld_accent'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .height(52)
          .onClick(() => {
            const name: string = this.name;
            const url: string = this.url;
            this.controller.close();
            this.onConfirm(name, url);
          })
      }
      .width('100%')
    }
    // 三项都不能少:customStyle 下宽度得自己给(不给就撑满屏宽);圆角用系统弹窗 token
    // 与其它弹窗一致;clip 是关键 —— 底部按钮的按压高亮是矩形,不裁剪会从圆角处溢出一块
    // 深色直角。与 SitesPage 的站点编辑弹窗保持同款。
    .width('86%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius($r('sys.float.ohos_id_corner_radius_dialog'))
    .clip(true)
  }
}

/**
 * 论坛管理页:添加 / 切换 / 删除 App 原生浏览的论坛。
 *
 * 与「我的站点」(SitesPage)刻意分开:那边是用 WebView 打开的生态站点快捷方式,不影响主站;
 * 这里切换论坛,全 app 的接口地址会跟着换,读的也是那个论坛的登录态。
 *
 * ## 切换 ≠ 退出登录
 * cookie 由系统 WebCookieManager 按域名分仓存放,切走不会碰原论坛的 cookie —— 切回来
 * 仍是登录状态,各论坛的账号长期并存。切换时重置的只是 App 侧那份「当前登录用户」的内存/
 * 镜像状态,并对新论坛重新查一次会话;这是必须的,否则会把上一个论坛的用户名显示在新论坛上。
 */
@Component
export struct ForumsPage {
  // 窗口常驻全屏布局:内容层自行避让状态栏(背景层已天然铺满整屏)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  onBack: () => void = () => {};
  @State private forums: ForumDef[] = [];
  @State private activeId: string = '';
  private scroller: Scroller = new Scroller();
  private editDialog: CustomDialogController | undefined = undefined;

  aboutToAppear(): void {
    this.reload();
  }

  // 卡片分组容器:无描边,靠灰底衬托。与设置页/各设置子页同款。
  @Styles
  cardStyle() {
    .width('100%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius(CARD_RADIUS)
    .margin({ top: CARD_GAP })
  }

  build() {
    // 与「我的站点」同款结构:内容层自行避让状态栏,标题栏作透明浮层叠在上面。
    Stack({ alignContent: Alignment.TopStart }) {
      this.ScrollableContent()
      this.TitleBarOverlay()
    }
    .width('100%')
    .height('100%')
    // 与设置页及其它设置子页一致:灰底衬托白卡片。用 page_bg 会与卡片同色,卡片就"看不见"了。
    .backgroundColor($r('app.color.page_bg_gray'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private ScrollableContent() {
    Scroll(this.scroller) {
      Column() {
        Blank()
          .height(immersiveTitleBarContentTopSpacer(this.sysTopInset))
        this.ForumListCard()
        this.AddButton()
        // 只在论坛少的时候露候选:列表长了之后这块纯属占地方。
        if (this.forums.length < 2) {
          this.SuggestionHint()
        }
        this.Footnote()
        Row()
          .width('100%')
          .height(40)
      }
      .width('100%')
      .padding({ left: PAGE_MARGIN, right: PAGE_MARGIN })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private TitleBarOverlay() {
    HdsNavigation() {
      Column()
        .width('100%')
        .height('100%')
    }
    .titleBar({
      avoidLayoutSafeArea: requiresHdsLayoutSafeAreaAvoidance(ImmersiveLightArea.TITLE_BAR),
      enableComponentSafeArea: requiresHdsComponentSafeArea(ImmersiveLightArea.TITLE_BAR),
      style: buildImmersiveTitleBarStyle(),
      content: {
        title: {
          mainTitle: '论坛'
        },
        backIcon: {
          icon: $r('sys.symbol.chevron_left'),
          label: '返回',
          action: () => {
            this.onBack();
          }
        },
        menu: {
          value: [{
            content: {
              icon: $r('sys.symbol.plus'),
              label: '添加论坛',
              isEnabled: true,
              action: () => {
                this.openAddDialog();
              }
            }
          }]
        }
      }
    })
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    // 只当标题栏容器用,不参与分栏(分栏由 RootTabPage 根 Navigation 负责)。
    .mode(NavigationMode.Stack)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private ForumListCard() {
    Column() {
      ForEach(this.forums, (forum: ForumDef, index: number) => {
        Row() {
          Column() {
            Text(forum.name)
              .fontSize(16)
              .fontWeight(forum.id === this.activeId ? FontWeight.Medium : FontWeight.Normal)
              .fontColor($r('app.color.text_primary'))
            Text(SiteUrl.hostOf(forum.baseUrl))
              .fontSize(12)
              .fontColor($r('app.color.text_faint'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (forum.id === this.activeId) {
            Text('当前')
              .fontSize(12)
              .fontColor($r('app.color.ld_accent'))
              .margin({ right: 8 })
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(18)
              .fontColor([$r('app.color.ld_accent')])
          } else {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.text_faint')])
          }
        }
        .width('100%')
        .padding({ top: 14, bottom: 14, left: CARD_PADDING, right: CARD_PADDING })
        .onClick(() => {
          this.switchTo(forum);
        })
        // 点击 = 切换(主操作),所以编辑只能另给一个手势。长按开编辑弹窗,删除入口在弹窗里。
        .gesture(
          LongPressGesture({ repeat: false, duration: 300 })
            .onAction(() => {
              this.openEditDialog(forum);
            })
        )

        if (index < this.forums.length - 1) {
          Divider()
            .strokeWidth(0.5)
            .color($r('app.color.border'))
            .margin({ left: CARD_PADDING })
        }
        // key 必须并入这一行实际渲染到的一切:ForEach 按 key 复用,key 不变就不重建。
        // 只用 id 的话,改完名字 key 没变 → 复用旧行 → 名字不刷新(要退出页面重进才对);
        // activeId 也得并进来,否则切换当前论坛时「当前」标记不会跟着挪。
        // (SitesPage 的站点快捷条早踩过同一个坑,那里把 iconUri 并进了 key。)
      }, (forum: ForumDef) => `${forum.id}_${forum.name}_${forum.baseUrl}_${forum.id === this.activeId}`)
    }
    .cardStyle()
  }

  @Builder
  private AddButton() {
    Row() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(18)
        .fontColor([$r('app.color.ld_accent')])
      Text('添加论坛')
        .fontSize(16)
        .fontColor($r('app.color.ld_accent'))
        .margin({ left: 8 })
    }
    .justifyContent(FlexAlign.Center)
    .padding({ top: 14, bottom: 14 })
    .cardStyle()
    .onClick(() => {
      this.openAddDialog();
    })
  }

  @Builder
  private SuggestionHint() {
    Column() {
      Text('可以试试这些公开论坛')
        .fontSize(13)
        .fontColor($r('app.color.text_faint'))
        .width('100%')
        .margin({ top: 24, bottom: 10 })

      Column() {
        ForEach(FORUM_SUGGESTIONS, (item: ForumSuggestion, index: number) => {
          Row() {
            Column() {
              Text(item.name)
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Text(SiteUrl.hostOf(item.baseUrl))
                .fontSize(12)
                .fontColor($r('app.color.text_faint'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.plus_circle'))
              .fontSize(18)
              .fontColor([$r('app.color.text_faint')])
          }
          .width('100%')
          .padding({ top: 12, bottom: 12, left: CARD_PADDING, right: CARD_PADDING })
          .onClick(() => {
            this.addForum(item.name, item.baseUrl, false);
          })

          if (index < FORUM_SUGGESTIONS.length - 1) {
            Divider()
              .strokeWidth(0.5)
              .color($r('app.color.border'))
              .margin({ left: CARD_PADDING })
          }
        }, (item: ForumSuggestion) => item.baseUrl)
      }
      .cardStyle()
    }
    .width('100%')
  }

  @Builder
  private Footnote() {
    Text('各论坛的账号彼此独立并长期保留:切换不会退出登录,切回来仍是登录状态。长按可改名、改地址或删除。')
      .fontSize(12)
      .lineHeight(18)
      .fontColor($r('app.color.text_faint'))
      .width('100%')
      .margin({ top: 16 })
  }

  // ==================== 逻辑 ====================

  private hostContext(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private reload(): void {
    const context: common.Context = this.hostContext();
    this.forums = ForumPrefs.getForums(context);
    this.activeId = ForumPrefs.getActiveId(context);
  }

  private openAddDialog(): void {
    this.editDialog = new CustomDialogController({
      builder: ForumEditDialog({
        isEdit: false,
        initialName: '',
        initialUrl: '',
        onConfirm: (name: string, url: string) => {
          this.addForum(name, url, false);
        }
      }),
      autoCancel: true,
      customStyle: true,
      alignment: DialogAlignment.Center
    });
    this.editDialog.open();
  }

  private openEditDialog(forum: ForumDef): void {
    this.editDialog = new CustomDialogController({
      builder: ForumEditDialog({
        isEdit: true,
        initialName: forum.name,
        initialUrl: forum.baseUrl,
        onConfirm: (name: string, url: string) => {
          this.saveForum(forum, name, url);
        },
        onDelete: () => {
          this.confirmRemove(forum);
        }
      }),
      autoCancel: true,
      customStyle: true,
      alignment: DialogAlignment.Center
    });
    this.editDialog.open();
  }

  /**
   * 保存编辑。改地址等于换了个站,若改的正是当前论坛,refreshActive 会按切站处理
   * (重建宿主、清缓存、刷列表);只改名字则仅刷标题等镜像,不惊动这些。
   */
  private saveForum(forum: ForumDef, name: string, urlInput: string): void {
    const context: common.Context = this.hostContext();
    const result: ForumUpdateResult = ForumPrefs.updateForum(context, forum.id, name, urlInput);
    if (!result.ok) {
      promptToast(this.getUIContext(), result.reason);
      return;
    }
    if (forum.id === this.activeId) {
      CurrentSite.refreshActive(context);
    }
    this.reload();
    Log.i(`${LOG_TAG} updated ${forum.id}`);
  }

  /**
   * 添加论坛。已存在同 host 时 addForum 返回既有项,此处据此提示,免得用户以为没加上。
   * switchAfterAdd=false:在管理页里添加不自动切走,免得正在浏览的内容被换掉;
   * 唯一例外是列表原本为空(那时没有「正在浏览」可言),由 reconcile 自然选中。
   */
  private addForum(name: string, urlInput: string, switchAfterAdd: boolean): void {
    const context: common.Context = this.hostContext();
    const before: number = ForumPrefs.getForums(context).length;
    const added: ForumDef | undefined = ForumPrefs.addForum(context, name, urlInput);
    if (!added) {
      promptToast(this.getUIContext(), '地址不正确,请填形如 example.com 的论坛域名');
      return;
    }
    const after: number = ForumPrefs.getForums(context).length;
    if (after === before) {
      promptToast(this.getUIContext(), `${added.name} 已在列表里`);
      this.reload();
      return;
    }
    // 列表原本为空时 reconcile 会把它选为当前论坛;否则保持当前不变。
    CurrentSite.reconcile(context);
    this.reload();
    Log.i(`${LOG_TAG} added ${added.baseUrl}`);
    if (switchAfterAdd) {
      this.switchTo(added);
    } else {
      promptToast(this.getUIContext(), `已添加 ${added.name}`);
    }
  }

  private switchTo(forum: ForumDef): void {
    if (forum.id === this.activeId) {
      return;
    }
    const context: common.Context = this.hostContext();
    if (CurrentSite.switchTo(context, forum)) {
      this.reload();
      promptToast(this.getUIContext(), `已切换到 ${forum.name}`);
    }
  }

  private confirmRemove(forum: ForumDef): void {
    this.getUIContext().showAlertDialog({
      title: '删除论坛',
      message: `确定要从列表中删除 ${forum.name} 吗?`,
      buttons: [
        { value: '取消', action: () => {} },
        {
          value: '删除',
          fontColor: $r('app.color.ld_danger'),
          action: () => {
            this.removeForum(forum);
          }
        }
      ]
    });
  }

  private removeForum(forum: ForumDef): void {
    const context: common.Context = this.hostContext();
    ForumPrefs.removeForum(context, forum.id);
    // 删掉的可能正是当前论坛:reconcile 负责重选(或在列表空掉时清成未配置,
    // 由 Index 顶回引导页)。
    CurrentSite.reconcile(context);
    this.reload();
    Log.i(`${LOG_TAG} removed ${forum.baseUrl}`);
  }
}
