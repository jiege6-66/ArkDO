import { CurrentSite } from '../../services/site/CurrentSite';
import { FORUM_SUGGESTIONS, ForumDef, ForumPrefs, ForumSuggestion } from '../../services/site/ForumPrefs';
import { Log } from '../../services/logging/Log';
import { SiteUrl } from '../../services/site/SiteUrl';
import { showToast as promptToast } from '../../common/utils/Toast';
import { common } from '@kit.AbilityKit';

const LOG_TAG: string = '[ArkDO][Onboarding]';

/**
 * 首启引导:选定第一个论坛。
 *
 * 一个论坛都没有时由 Index 顶替 RootTabPage 全屏显示 —— 不是路由页,因为此时整个
 * App 还没有可用的站点地址,进不了主界面的任何一屏。
 *
 * 刻意不预置任何站点:ArkDO 是通用 Discourse 客户端,内容来自用户自己添加的论坛。
 * 下面那几个候选只是「示例」,点一下等于替用户省掉打字,不代表与这些站点有任何关系。
 */
@Component
export struct ForumOnboardingPage {
  @State private urlInput: string = '';
  @State private adding: boolean = false;

  build() {
    Scroll() {
      Column() {
        this.Header()
        this.InputCard()
        this.SuggestionCard()
        this.Disclaimer()
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 32 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }

  @Builder
  private Header() {
    Column() {
      Image($r('app.media.app_logo'))
        .width(72)
        .height(72)
        .margin({ bottom: 18 })

      Text('先添加一个论坛')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      Text('ArkDO 是通用的论坛客户端，支持基于 Discourse（开源论坛程序）搭建的站点。填入论坛地址即可开始浏览。')
        .fontSize(14)
        .lineHeight(21)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ top: 10 })
    }
    .width('100%')
    .padding({ top: 72, bottom: 28 })
  }

  @Builder
  private InputCard() {
    Column() {
      TextInput({ placeholder: '论坛地址，如 meta.discourse.org', text: this.urlInput })
        .fontSize(15)
        .height(48)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(12)
        .enterKeyType(EnterKeyType.Done)
        .onChange((value: string) => {
          this.urlInput = value;
        })
        .onSubmit(() => {
          this.addAndEnter(this.urlInput, '');
        })

      Button(this.adding ? '正在添加...' : '添加并进入')
        .type(ButtonType.Normal)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.ld_accent'))
        .borderRadius(12)
        .width('100%')
        .height(48)
        .margin({ top: 12 })
        .enabled(!this.adding && this.urlInput.trim().length > 0)
        .onClick(() => {
          this.addAndEnter(this.urlInput, '');
        })
    }
    .width('100%')
  }

  @Builder
  private SuggestionCard() {
    Column() {
      Text('或从这些公开论坛试起')
        .fontSize(13)
        .fontColor($r('app.color.text_faint'))
        .width('100%')
        .margin({ top: 30, bottom: 10 })

      Column() {
        ForEach(FORUM_SUGGESTIONS, (item: ForumSuggestion, index: number) => {
          Row() {
            Column() {
              Text(item.name)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text(`${item.desc} · ${SiteUrl.hostOf(item.baseUrl)}`)
                .fontSize(12)
                .fontColor($r('app.color.text_faint'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.text_faint')])
          }
          .width('100%')
          .padding({ top: 14, bottom: 14, left: 16, right: 16 })
          .onClick(() => {
            this.addAndEnter(item.baseUrl, item.name);
          })

          if (index < FORUM_SUGGESTIONS.length - 1) {
            Divider()
              .strokeWidth(0.5)
              .color($r('app.color.border'))
              .margin({ left: 16 })
          }
        }, (item: ForumSuggestion) => item.baseUrl)
      }
      .width('100%')
      .backgroundColor($r('app.color.surface_muted'))
      .borderRadius(16)
    }
    .width('100%')
  }

  @Builder
  private Disclaimer() {
    Text('本应用不提供、不托管、不审核任何内容。所有内容均来自你自行添加的第三方站点，由该站点及其运营方负责。本应用与任何论坛站点及其运营方无隶属、合作或授权关系。')
      .fontSize(11)
      .lineHeight(17)
      .fontColor($r('app.color.text_faint'))
      .textAlign(TextAlign.Center)
      .margin({ top: 28 })
  }

  // ==================== 逻辑 ====================

  private hostContext(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  /**
   * 添加论坛并进入主界面。
   *
   * 这里不做「地址是否真是 Discourse」的联网探测:引导页还没有可用的宿主 webview
   * (它本身就要按站点 origin 才能建起来),探测无从下手。填错的结果是进主界面后
   * 拉不到列表并给出重试,用户可以回论坛管理页改——比在引导页卡住更好收场。
   */
  private addAndEnter(urlInput: string, name: string): void {
    if (this.adding) {
      return;
    }
    const baseUrl: string = SiteUrl.toBaseUrl(urlInput);
    if (baseUrl.length === 0) {
      promptToast(this.getUIContext(), '地址不正确，请填形如 example.com 的论坛域名');
      return;
    }
    this.adding = true;
    const context: common.Context = this.hostContext();
    const added: ForumDef | undefined = ForumPrefs.addForum(context, name, baseUrl);
    if (!added) {
      this.adding = false;
      promptToast(this.getUIContext(), '添加失败，请检查地址');
      return;
    }
    // reconcile 会选中它并推入 AppConstants,同时刷新 AppStorage 镜像 ——
    // Index 监听该镜像,于是本页被 RootTabPage 顶替。
    CurrentSite.reconcile(context);
    Log.i(`${LOG_TAG} added and entered: ${added.baseUrl}`);
    this.adding = false;
  }
}
