import { curves, FrameCallback, KeyboardAvoidMode, UIContext } from '@kit.ArkUI';
import window from '@ohos.window';
import { common } from '@kit.AbilityKit';
import resourceManager from '@ohos.resourceManager';
import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';
import { EmojiPicker } from './EmojiPicker';
import {
  EmojiItem,
  ensureEmojiUrlsLoaded,
  getEmojiItem,
  getEmojiNameByUrl,
  getEmojiUrl
} from './EmojiUrlRegistry';
import { COMPOSER_GEOMETRY_ID } from '../pages/ComposerPage';
import { showToast as promptToast } from '../../common/utils/Toast';
import { BRAND_BLUE, ON_DARK_FG, SCRIM } from '../../common/theme/Palette';
import { IMMERSIVE_PANEL_BLUR_RADIUS } from '../../common/ui/ImmersiveLightMaterial';
import { EditState, insertText } from '../../utils/markdownInsert';
import { BoostEditDocument, BoostEditToken, BoostTokenType } from '../../models/BoostEditDocument';
import { COMPOSER_OVERLAY_BACK_TICK_KEY } from '../../common/constants/StorageKeys';
import { EmojiDeleteResult, EmojiShortcodeEdit } from '../../utils/EmojiShortcodeEdit';
import {
  COMMENT_INPUT_EMOJI_SIZE,
  COMMENT_INPUT_EMOJI_VERTICAL_MARGIN,
  COMMENT_INPUT_HALF_LEADING,
  COMMENT_INPUT_LINE_HEIGHT,
  COMMENT_INPUT_MAX_HEIGHT,
  COMMENT_INPUT_PADDING_BOTTOM,
  COMMENT_INPUT_PADDING_TOP,
  COMMENT_INPUT_SINGLE_LINE_HEIGHT,
  commentKeyboardToggleIcon,
  commentInputHeightForLineHeights,
  shouldShowCommentInputPlaceholder
} from './CommentInputPresentation';

// Discourse 经典蓝，作回复按钮背景（rgb(0,136,204)）。页面的悬浮回复按钮也复用此色。
export const REPLY_BLUE: string = BRAND_BLUE;
// 输入框最小/最高高度：低于最小高度不再缩，超过最高高度 TextArea 内部滚动。
// 最小高度给足竖向空间，避免光标上下被截。
const INPUT_MIN_HEIGHT: number = COMMENT_INPUT_SINGLE_LINE_HEIGHT;
const INPUT_MAX_HEIGHT: number = COMMENT_INPUT_MAX_HEIGHT;
// 输入框获取焦点用的 id：挂载后 requestFocus 弹出软键盘。
const INPUT_FOCUS_ID: string = 'arkdoCommentInput';
const EMOJI_PANEL_MIN_HEIGHT: number = 280;
const EMOJI_PANEL_DEFAULT_HEIGHT: number = 300;
// maxChars 取该值表示不限字数（回复走这条）。
export const NO_MAX_CHARS: number = 0;

class CommentInputNextFrameTask extends FrameCallback {
  private readonly run: () => void;

  constructor(run: () => void) {
    super();
    this.run = run;
  }

  onFrame(_frameTimeInNano: number): void {
    this.run();
  }

  onIdle(_timeLeftInNano: number): void {
  }
}

// 键盘上方的评论输入浮层（由 TopicDetailPage 直接内联挂在页面根 Stack 顶层）：
// - 内联渲染 → getLastWindow 拿到的就是主窗口，能稳定收到键盘事件；监听 avoidAreaChange
//   拿到 TYPE_KEYBOARD 避让高度，手动把输入条按该高度上移到键盘上方（背后列表不动）。
// - 全屏布局由页面(TopicDetailPage)在展开评论时切换（并给背后主内容补状态栏高度抵消位移），
//   全屏下遮罩能盖住状态栏、输入条按 margin=键盘高度贴到键盘上沿。
// - 键盘收起时输入条底部叠加底部安全区内边距贴 Home 条之上；键盘弹起时上移键盘高度、收掉这段内边距。
@Component
export struct CommentInputBar {
  onClose: () => void = () => {};
  // 输入框占位文字：回复话题为「回复当前话题」，回复某楼为「回复<昵称>」，由页面传入。
  placeholder: string = '写下你的评论…';
  // 正文最短字数：少于该值不允许提交。评论默认 16（对齐 Discourse 最短回复），
  // boost 这类短文本由页面传入更小的值（如 1）。
  minChars: number = 16;
  // 正文最长字数：NO_MAX_CHARS 表示不限（回复走这条）。boost 服务端上限 16，超出会被 422
  // 打回且不带原因，只能在客户端先拦住。
  maxChars: number = NO_MAX_CHARS;
  // 表情富文本输入：选择的表情直接渲染成图片 Span，并按一个字符计数。
  // 当前普通回复与 Boost 都开启；保留开关方便其它纯文本调用方复用。
  richEmojiMode: boolean = false;
  // 官方 Boost 从表情选择器插入表情时，会在已有文字与短码之间加一个空格。
  spaceBeforeSelectedEmoji: boolean = false;
  // 返回 true 表示提交成功（浮层随即清空并关闭）；false 表示失败（保留内容供重试）。
  onSubmit: (text: string, typingMs: number, composerMs: number) => Promise<boolean> =
    (text: string, typingMs: number, composerMs: number) => Promise.resolve(false);
  // 是否显示「展开到全屏编辑器」按钮：普通回复显示，boost（短文本，服务端上限 16 字）不显示。
  showExpand: boolean = false;
  // 点「展开」上抛当前已输入文本 + 当前键盘高度（vp），由页面关闭内联浮层并压入全屏编辑器
  // （ComposerPage）无缝接续。带键盘高度是为了让全屏页首帧就按「有键盘」布局，避免从 0 起跳
  // 导致工具栏先落底再上移的「回缩一下」。
  onExpand: (currentText: string, keyboardHeight: number) => void = () => {};
  // 初始正文:页面把上次未发出的内容带回来(关掉输入条再点开,内容还在)。
  initialText: string = '';
  // 文本变化时上抛给页面暂存。内联条一关就卸载、@State 随之销毁,不上抛就彻底丢了。
  onTextChange: (text: string) => void = () => {};
  @State private text: string = '';
  @State private isSubmitting: boolean = false;
  // 当前键盘高度（vp）；0 表示键盘收起。
  @State private keyboardHeight: number = 0;
  @State private showEmojiKeyboard: boolean = false;
  @State private emojiPanelHeight: number = EMOJI_PANEL_DEFAULT_HEIGHT;
  @State private boostLogicalLength: number = 0;
  @State private richEditorHeight: number = INPUT_MIN_HEIGHT;
  @StorageProp(COMPOSER_OVERLAY_BACK_TICK_KEY) @Watch('onComposerBackTick') private composerBackTick: number = 0;
  // 底部安全区高度（vp，挂载时读一次，用于键盘收起时的底部内边距）。
  @State private bottomInset: number = 0;
  private winClass?: window.Window = undefined;
  private focusTimer: number = -1;
  private lastKeyboardHeight: number = EMOJI_PANEL_DEFAULT_HEIGHT;
  private selectionStart: number = 0;
  private selectionEnd: number = 0;
  private textController: TextAreaController = new TextAreaController();
  private richController: RichEditorController = new RichEditorController();
  private richEditorReady: boolean = false;
  private heightRefreshPending: boolean = false;
  // 浮层出现的时刻 / 首次输入的时刻，用于回填 composer_open / typing 时长（对齐官方遥测字段）。
  private appearTimeMs: number = 0;
  private firstTypeTimeMs: number = 0;
  // 上一次 onChange 时是否已超上限：用于只在「刚超出」的那一下弹提示。
  private wasOverMaxChars: boolean = false;
  // 绑定 this，方便 off 时传入同一引用注销。监听键盘避让区变化拿键盘高度（本机已验证有效）。
  private onAvoidAreaChange: (data: window.AvoidAreaOptions) => void = (data: window.AvoidAreaOptions) => {
    if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
      // 键盘避让矩形高度 = 键盘顶到屏幕底的遮挡高度；收起时为 0。
      const height: number = this.getUIContext().px2vp(data.area.bottomRect.height);
      if (height > 0) {
        this.lastKeyboardHeight = height;
      }
      // 用显式 animateTo 驱动上移动画（不在输入条/图标的父容器上挂 .animation，避免图标不渲染）。
      // 曲线取系统输入法面板同款弹簧曲线(输入法框架统一驱动面板动画,与具体输入法 App 无关),
      // 让输入条与键盘几乎逐帧同步;弹簧曲线时长由物理参数决定,不需要 duration。
      this.getUIContext().animateTo({ curve: curves.interpolatingSpring(0, 1, 342, 38) }, () => {
        this.keyboardHeight = height;
        // 切回文字键盘时先保留表情面板占位，等真实键盘高度到达后再同帧替换，避免输入条先落底再弹起。
        if (height > 0 && this.showEmojiKeyboard) {
          this.showEmojiKeyboard = false;
        }
      });
    }
  };

  aboutToAppear(): void {
    this.appearTimeMs = Date.now();
    // 富文本编辑器必须在解析初始草稿前拿到短码索引，否则首次打开表情面板前无法还原已有表情。
    const manager: resourceManager.ResourceManager =
      (this.getUIContext().getHostContext() as common.Context).resourceManager;
    ensureEmojiUrlsLoaded(manager);
    // 带回上次未发出的内容(页面暂存的)。
    this.text = this.initialText;
    this.selectionStart = this.initialText.length;
    this.selectionEnd = this.initialText.length;
    if (this.richEmojiMode) {
      this.boostLogicalLength = BoostEditDocument.logicalLengthOfRaw(this.initialText,
        (name: string): boolean => getEmojiUrl(name) !== undefined);
    }
    // 关闭系统默认整页键盘避让，改为自己按键盘高度上移输入条（背后页面不动）。
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);

    window.getLastWindow(this.getUIContext().getHostContext() as common.Context).then((win: window.Window) => {
      this.winClass = win;
      const sysArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.bottomInset = this.getUIContext().px2vp(sysArea.bottomRect.height);
      // 内联挂载时 getLastWindow 即主窗口，键盘避让事件能稳定收到。
      win.on('avoidAreaChange', this.onAvoidAreaChange);
    }).catch(() => {
      // 拿不到 window 时退化为不偏移（输入条仍在底部），不影响输入本身。
    });
  }

  aboutToDisappear(): void {
    if (this.focusTimer >= 0) {
      clearTimeout(this.focusTimer);
      this.focusTimer = -1;
    }
    if (this.winClass) {
      this.winClass.off('avoidAreaChange', this.onAvoidAreaChange);
      this.winClass = undefined;
    }
    // 还原默认避让模式，避免影响后续其它页面的输入场景。
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET);
  }

  private focusInput(): void {
    // 挂载后主动请求焦点弹出软键盘。
    this.focusTimer = setTimeout(() => {
      this.getUIContext().getFocusController().requestFocus(INPUT_FOCUS_ID);
    }, 200);
  }

  private hideKeyboard(): void {
    // 让编辑器正常失焦并由 ArkUI 收起键盘；保留焦点会导致后续 requestFocus 成为空操作。
    if (this.richEmojiMode && this.richEditorReady) {
      const selection: [number, number] = this.richController.getSelection().selection;
      if (selection[0] >= 0 && selection[1] >= 0) {
        this.selectionStart = selection[0];
        this.selectionEnd = selection[1];
      }
    }
    this.getUIContext().getFocusController().clearFocus();
  }

  private showSystemKeyboard(): void {
    // 不在这里提前卸载表情面板；onAvoidAreaChange 收到系统键盘高度后再完成替换。
    setTimeout(() => {
      this.getUIContext().getFocusController().requestFocus(INPUT_FOCUS_ID);
      if (this.richEmojiMode && this.richEditorReady) {
        this.richController.setSelection(this.selectionStart, this.selectionEnd);
      } else {
        this.textController.setTextSelection(this.selectionStart, this.selectionEnd);
      }
    }, 60);
  }

  private toggleEmojiKeyboard(): void {
    if (this.showEmojiKeyboard) {
      this.showSystemKeyboard();
      return;
    }
    const targetHeight: number = this.keyboardHeight > 0 ? this.keyboardHeight : this.lastKeyboardHeight;
    this.emojiPanelHeight = Math.max(EMOJI_PANEL_MIN_HEIGHT, targetHeight);
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.showEmojiKeyboard = true;
    });
    this.hideKeyboard();
  }

  private activeBottomOffset(): number {
    if (this.showEmojiKeyboard) {
      return this.emojiPanelHeight + this.bottomInset;
    }
    return this.keyboardHeight;
  }

  private onComposerBackTick(): void {
    if (this.showEmojiKeyboard) {
      this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.showEmojiKeyboard = false;
      });
      return;
    }
    this.onClose();
  }

  private showToast(message: string, duration: number): void {
    promptToast(this.getUIContext(), message, duration);
  }

  private trimmedLength(): number {
    return this.richEmojiMode ? this.boostLogicalLength : this.text.trim().length;
  }

  private overMaxChars(): boolean {
    return this.maxChars > NO_MAX_CHARS && this.trimmedLength() > this.maxChars;
  }

  // 超出上限时提示。不硬顶输入（硬顶会静默吞字，用户不知道发生了什么），改为让字打进来再告知，
  // 由发送按钮置灰 + submit() 兜底拦住提交。每次「由未超变超」才弹一次，连着多打不会刷屏。
  private warnIfOverMaxChars(): void {
    const over: boolean = this.overMaxChars();
    if (over && !this.wasOverMaxChars) {
      this.showToast(`最多 ${this.maxChars} 个字`, 1500);
    }
    this.wasOverMaxChars = over;
  }

  private canSubmit(): boolean {
    return !this.isSubmitting && this.trimmedLength() >= this.minChars && !this.overMaxChars();
  }

  private async submit(): Promise<void> {
    if (this.isSubmitting) {
      return;
    }
    const trimmed: string = this.text.trim();
    if (this.trimmedLength() < this.minChars) {
      // 少于最短字数：提示还差多少字，不提交。
      const need: number = this.minChars - this.trimmedLength();
      this.showToast(`至少还需 ${need} 个字`, 1500);
      return;
    }
    if (this.overMaxChars()) {
      // 超出最长字数：提示需删掉多少字，不提交（服务端只会回不带原因的 422）。
      const over: number = this.trimmedLength() - this.maxChars;
      this.showToast(`超出 ${over} 个字，最多 ${this.maxChars} 字`, 1500);
      return;
    }
    this.isSubmitting = true;
    const typingMs: number = this.firstTypeTimeMs > 0 ? Date.now() - this.firstTypeTimeMs : 0;
    const composerMs: number = this.appearTimeMs > 0 ? Date.now() - this.appearTimeMs : 0;
    let ok: boolean = false;
    try {
      ok = await this.onSubmit(trimmed, typingMs, composerMs);
    } catch (error) {
      ok = false;
    }
    this.isSubmitting = false;
    if (ok) {
      this.text = '';
      this.onClose();
    }
  }

  private insertSelectedEmoji(emoji: EmojiItem): void {
    if (this.richEmojiMode) {
      this.insertBoostEmoji(emoji);
      return;
    }
    const current: EditState = {
      text: this.text,
      selectionStart: this.selectionStart,
      selectionEnd: this.selectionEnd
    };
    const next: EditState = insertText(current, `:${emoji.name}:`);
    this.text = next.text;
    this.selectionStart = next.selectionStart;
    this.selectionEnd = next.selectionEnd;
    this.onTextChange(next.text);
    if (this.firstTypeTimeMs === 0) {
      this.firstTypeTimeMs = Date.now();
    }
    setTimeout(() => {
      this.textController.setTextSelection(next.selectionStart, next.selectionEnd);
    }, 0);
  }

  private onWillDeleteText(value: DeleteValue): boolean {
    if (this.selectionStart !== this.selectionEnd) {
      return true;
    }
    const result: EmojiDeleteResult | undefined = value.direction === TextDeleteDirection.BACKWARD
      ? EmojiShortcodeEdit.deleteBackward(this.text, this.selectionStart,
        (name: string): boolean => getEmojiUrl(name) !== undefined)
      : EmojiShortcodeEdit.deleteForward(this.text, this.selectionStart,
        (name: string): boolean => getEmojiUrl(name) !== undefined);
    if (!result) {
      return true;
    }
    this.text = result.text;
    this.selectionStart = result.caret;
    this.selectionEnd = result.caret;
    this.onTextChange(result.text);
    this.warnIfOverMaxChars();
    setTimeout(() => {
      this.textController.caretPosition(result.caret);
    }, 0);
    return false;
  }

  private deleteFromEmojiKeyboard(): void {
    if (this.richEmojiMode) {
      this.deleteBoostContent();
      return;
    }
    const start: number = Math.min(this.selectionStart, this.selectionEnd);
    const end: number = Math.max(this.selectionStart, this.selectionEnd);
    let result: EmojiDeleteResult | undefined;
    if (end > start) {
      result = {
        text: this.text.substring(0, start) + this.text.substring(end),
        caret: start
      };
    } else {
      result = EmojiShortcodeEdit.deleteBackward(this.text, start,
        (name: string): boolean => getEmojiUrl(name) !== undefined);
      if (!result) {
        result = EmojiShortcodeEdit.deletePreviousCharacter(this.text, start);
      }
    }
    if (!result) {
      return;
    }
    this.text = result.text;
    this.selectionStart = result.caret;
    this.selectionEnd = result.caret;
    this.onTextChange(result.text);
    this.warnIfOverMaxChars();
    this.textController.caretPosition(result.caret);
  }

  private deleteBoostContent(): void {
    if (!this.richEditorReady) {
      return;
    }
    const selection: [number, number] = this.savedRichSelection();
    let start: number = Math.min(selection[0], selection[1]);
    const end: number = Math.max(selection[0], selection[1]);
    if (start === end) {
      if (start <= 0) {
        return;
      }
      start--;
    }
    this.richController.deleteSpans({ start: start, end: end });
    this.richController.setCaretOffset(start);
    this.selectionStart = start;
    this.selectionEnd = start;
    this.syncBoostText();
  }

  private insertBoostEmoji(emoji: EmojiItem): void {
    if (!this.richEditorReady) {
      return;
    }
    const selection: [number, number] = this.savedRichSelection();
    const start: number = Math.min(selection[0], selection[1]);
    const end: number = Math.max(selection[0], selection[1]);
    const total: number = this.richContentLength();
    const candidate: BoostEditToken[] = this.richTokensFromRange(0, start);
    const needsSpace: boolean = this.spaceBeforeSelectedEmoji && BoostEditDocument.needsSpaceBeforeEmoji(candidate);
    if (needsSpace) {
      candidate.push({ type: BoostTokenType.TEXT, value: ' ' });
    }
    candidate.push({ type: BoostTokenType.EMOJI, value: emoji.name });
    const tail: BoostEditToken[] = this.richTokensFromRange(end, total);
    for (let index: number = 0; index < tail.length; index++) {
      candidate.push(tail[index]);
    }
    if (this.maxChars > NO_MAX_CHARS && BoostEditDocument.logicalLengthTrimmed(candidate) > this.maxChars) {
      this.showToast(`最多 ${this.maxChars} 个字`, 1500);
      return;
    }
    if (end > start) {
      this.richController.deleteSpans({ start: start, end: end });
    }
    let emojiOffset: number = start;
    if (needsSpace) {
      this.richController.addTextSpan(' ', {
        offset: start,
        style: {
          fontSize: 16,
          fontColor: $r('app.color.text_primary'),
          lineHeight: COMMENT_INPUT_LINE_HEIGHT,
          halfLeading: COMMENT_INPUT_HALF_LEADING
        }
      });
      emojiOffset++;
    }
    this.richController.addImageSpan(emoji.url, {
      offset: emojiOffset,
      imageStyle: {
        size: [COMMENT_INPUT_EMOJI_SIZE, COMMENT_INPUT_EMOJI_SIZE],
        verticalAlign: ImageSpanAlignment.CENTER,
        objectFit: ImageFit.Contain,
        layoutStyle: {
          margin: {
            top: COMMENT_INPUT_EMOJI_VERTICAL_MARGIN,
            bottom: COMMENT_INPUT_EMOJI_VERTICAL_MARGIN
          }
        }
      }
    });
    const caret: number = emojiOffset + 1;
    this.richController.setCaretOffset(caret);
    this.selectionStart = caret;
    this.selectionEnd = caret;
    this.syncBoostText();
  }

  private hydrateBoostEditor(): void {
    this.richController.deleteSpans();
    const tokens: BoostEditToken[] = BoostEditDocument.parse(this.initialText,
      (name: string): boolean => getEmojiUrl(name) !== undefined);
    let offset: number = 0;
    for (let index: number = 0; index < tokens.length; index++) {
      const token: BoostEditToken = tokens[index];
      if (token.type === BoostTokenType.EMOJI) {
        const emoji: EmojiItem | undefined = getEmojiItem(token.value);
        if (emoji) {
          this.richController.addImageSpan(emoji.url, {
            offset: offset,
            imageStyle: {
              size: [COMMENT_INPUT_EMOJI_SIZE, COMMENT_INPUT_EMOJI_SIZE],
              verticalAlign: ImageSpanAlignment.CENTER,
              objectFit: ImageFit.Contain,
              layoutStyle: {
                margin: {
                  top: COMMENT_INPUT_EMOJI_VERTICAL_MARGIN,
                  bottom: COMMENT_INPUT_EMOJI_VERTICAL_MARGIN
                }
              }
            }
          });
          offset++;
        }
      } else {
        this.richController.addTextSpan(token.value, {
          offset: offset,
          style: {
            fontSize: 16,
            fontColor: $r('app.color.text_primary'),
            lineHeight: COMMENT_INPUT_LINE_HEIGHT,
            halfLeading: COMMENT_INPUT_HALF_LEADING
          }
        });
        offset += token.value.length;
      }
    }
    this.richController.setCaretOffset(offset);
    this.selectionStart = offset;
    this.selectionEnd = offset;
    this.richEditorReady = true;
    this.syncBoostText();
  }

  private richContentLength(): number {
    const spans: Array<RichEditorImageSpanResult | RichEditorTextSpanResult> = this.richController.getSpans();
    if (spans.length === 0) {
      return 0;
    }
    return spans[spans.length - 1].spanPosition.spanRange[1];
  }

  private savedRichSelection(): [number, number] {
    const contentLength: number = this.richContentLength();
    const start: number = Math.max(0, Math.min(this.selectionStart, contentLength));
    const end: number = Math.max(0, Math.min(this.selectionEnd, contentLength));
    return [start, end];
  }

  private richTokensFromRange(start: number, end: number): BoostEditToken[] {
    const tokens: BoostEditToken[] = [];
    if (end <= start) {
      return tokens;
    }
    const spans: Array<RichEditorImageSpanResult | RichEditorTextSpanResult> = this.richController.getSpans();
    for (let index: number = 0; index < spans.length; index++) {
      const span: RichEditorImageSpanResult | RichEditorTextSpanResult = spans[index];
      const spanStart: number = span.spanPosition.spanRange[0];
      const spanEnd: number = span.spanPosition.spanRange[1];
      const rangeStart: number = Math.max(start, spanStart);
      const rangeEnd: number = Math.min(end, spanEnd);
      if (rangeEnd <= rangeStart) {
        continue;
      }
      const imageSpan: RichEditorImageSpanResult = span as RichEditorImageSpanResult;
      if (imageSpan.valueResourceStr !== undefined) {
        if (typeof imageSpan.valueResourceStr === 'string') {
          const emojiName: string | undefined = getEmojiNameByUrl(imageSpan.valueResourceStr);
          if (emojiName) {
            tokens.push({ type: BoostTokenType.EMOJI, value: emojiName });
          }
        }
        continue;
      }
      const textSpan: RichEditorTextSpanResult = span as RichEditorTextSpanResult;
      const localStart: number = rangeStart - spanStart;
      const localEnd: number = rangeEnd - spanStart;
      const value: string = textSpan.value.substring(localStart, localEnd);
      if (value.length > 0) {
        tokens.push({ type: BoostTokenType.TEXT, value: value });
      }
    }
    return tokens;
  }

  private syncBoostText(): void {
    if (!this.richEditorReady) {
      return;
    }
    const tokens: BoostEditToken[] = this.richTokensFromRange(0, this.richContentLength());
    const raw: string = BoostEditDocument.serialize(tokens);
    this.text = raw;
    this.boostLogicalLength = BoostEditDocument.logicalLengthTrimmed(tokens);
    if (this.firstTypeTimeMs === 0 && raw.length > 0) {
      this.firstTypeTimeMs = Date.now();
    }
    this.onTextChange(raw);
    this.warnIfOverMaxChars();
    this.refreshRichEditorHeight();
  }

  // Boost 固定为单行输入；普通回复根据 RichEditor 实际排版行高增长，最多保持原输入条的 120vp。
  private refreshRichEditorHeight(): void {
    if (this.maxChars > NO_MAX_CHARS) {
      this.richEditorHeight = INPUT_MIN_HEIGHT;
      return;
    }
    if (this.heightRefreshPending) {
      return;
    }
    this.heightRefreshPending = true;
    this.getUIContext().postFrameCallback(new CommentInputNextFrameTask(() => {
      this.getUIContext().postFrameCallback(new CommentInputNextFrameTask(() => {
        this.heightRefreshPending = false;
        this.measureRichEditorHeight();
      }));
    }));
  }

  private measureRichEditorHeight(): void {
    if (!this.richEditorReady) {
      return;
    }
    try {
      const layout: LayoutManager = this.richController.getLayoutManager();
      const lineCount: number = layout.getLineCount();
      const lineHeights: number[] = [];
      const ui: UIContext = this.getUIContext();
      for (let index: number = 0; index < lineCount; index++) {
        lineHeights.push(ui.px2vp(layout.getLineMetrics(index).height));
      }
      this.richEditorHeight = commentInputHeightForLineHeights(lineHeights);
    } catch (err) {
      this.richEditorHeight = INPUT_MIN_HEIGHT;
    }
  }

  private canInsertBoostText(value: RichEditorInsertValue): boolean {
    if (this.maxChars <= NO_MAX_CHARS) {
      return true;
    }
    const selection: [number, number] = this.richController.getSelection().selection;
    let start: number = Math.min(selection[0], selection[1]);
    let end: number = Math.max(selection[0], selection[1]);
    if (start === end) {
      start = value.insertOffset;
      end = value.insertOffset;
    }
    const total: number = this.richContentLength();
    const tokens: BoostEditToken[] = this.richTokensFromRange(0, start);
    if (value.insertValue.length > 0) {
      tokens.push({ type: BoostTokenType.TEXT, value: value.insertValue });
    }
    const tail: BoostEditToken[] = this.richTokensFromRange(end, total);
    for (let index: number = 0; index < tail.length; index++) {
      tokens.push(tail[index]);
    }
    const allowed: boolean = BoostEditDocument.logicalLengthTrimmed(tokens) <= this.maxChars;
    if (!allowed) {
      this.showToast(`最多 ${this.maxChars} 个字`, 1500);
    }
    return allowed;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 遮罩层：点输入条以外区域收起键盘并关闭浮层。淡入淡出统一挂在根 Stack 上（见下方），
      // 这里不单独设 transition —— 组件被 if 移除时只有最外层节点的退出动画会播放。
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(SCRIM)
        .onClick(() => {
          this.onClose();
        })

      // 底部输入条：按键盘高度手动上移到键盘上方。
      Row({ space: 8 }) {
        // 展开按钮：仅普通回复显示（boost 短文本无需全屏编辑）。点击上抛当前文本，
        // 由页面关闭内联浮层、压入全屏 Markdown 编辑器无缝接续。
        if (this.showExpand) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
              .fontSize(20)
              .fontColor([$r('app.color.icon_secondary')])
          }
          .width(40)
          .height(40)
          .backgroundColor($r('app.color.immersive_input_field_bg'))
          .onClick(() => {
            this.onExpand(this.text, this.showEmojiKeyboard ? this.emojiPanelHeight : this.keyboardHeight);
          })
        }

        // 圆角输入容器：内放多行输入框。内边距全部放到 TextArea 上，让光标离圆角足够远、
        // 竖向留足空间；clip(false) 杜绝子内容被圆角裁切。
        Column() {
          if (this.richEmojiMode) {
            Stack({ alignContent: Alignment.TopStart }) {
              RichEditor({ controller: this.richController })
                .id(INPUT_FOCUS_ID)
                .width('100%')
                .height('100%')
                .backgroundColor(Color.Transparent)
                .barState(BarState.Off)
                .padding({
                  left: 12,
                  right: 12,
                  top: COMMENT_INPUT_PADDING_TOP,
                  bottom: COMMENT_INPUT_PADDING_BOTTOM
                })
                .defaultFocus(true)
                .enterKeyType(EnterKeyType.NEW_LINE)
                .aboutToIMEInput((value: RichEditorInsertValue): boolean => {
                  return this.canInsertBoostText(value);
                })
                .onDidChange((rangeBefore: TextRange, rangeAfter: TextRange) => {
                  this.syncBoostText();
                })
                .onSelectionChange((range: RichEditorRange) => {
                  // 失焦收起系统键盘时可能上报空选区；表情面板期间保留最后一个有效光标位置。
                  if (!this.showEmojiKeyboard) {
                    this.selectionStart = range.start !== undefined ? range.start : 0;
                    this.selectionEnd = range.end !== undefined ? range.end : this.selectionStart;
                  }
                })
                .onReady(() => {
                  this.richController.setTypingStyle({
                    fontSize: 16,
                    fontColor: $r('app.color.text_primary'),
                    lineHeight: COMMENT_INPUT_LINE_HEIGHT,
                    halfLeading: COMMENT_INPUT_HALF_LEADING
                  });
                  this.hydrateBoostEditor();
                })
                .onClick(() => {
                  if (this.showEmojiKeyboard) {
                    this.showSystemKeyboard();
                  }
                })

              if (shouldShowCommentInputPlaceholder(this.text)) {
                Text(this.placeholder)
                  .width('100%')
                  .height(INPUT_MIN_HEIGHT)
                  .padding({
                    left: 12,
                    right: 12,
                    top: COMMENT_INPUT_PADDING_TOP,
                    bottom: COMMENT_INPUT_PADDING_BOTTOM
                  })
                  .fontSize(16)
                  .lineHeight(COMMENT_INPUT_LINE_HEIGHT)
                  .halfLeading(COMMENT_INPUT_HALF_LEADING)
                  .fontColor($r('app.color.text_tertiary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .hitTestBehavior(HitTestMode.None)
              }
            }
              .width('100%')
              .height(this.richEditorHeight)
          } else {
            TextArea({ text: $$this.text, placeholder: this.placeholder, controller: this.textController })
              .id(INPUT_FOCUS_ID)
              .width('100%')
              .backgroundColor(Color.Transparent)
              // 纯文本回退模式保留原来的上下 10vp 内边距，避免光标被圆角裁切。
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .fontSize(16)
              // 行高 24 + 上下 padding 各 10 = 44，单行自然高度仍保持原有触控与光标空间。
              .lineHeight(24)
              .fontColor($r('app.color.text_primary'))
              .placeholderColor($r('app.color.text_tertiary'))
              .defaultFocus(true)
              .enterKeyType(EnterKeyType.NEW_LINE)
              .constraintSize({ minHeight: INPUT_MIN_HEIGHT, maxHeight: INPUT_MAX_HEIGHT })
              .onTextSelectionChange((start: number, end: number) => {
                this.selectionStart = start;
                this.selectionEnd = end;
              })
              .onWillDelete((value: DeleteValue): boolean => {
                return this.onWillDeleteText(value);
              })
              .onChange((value: string) => {
                if (this.firstTypeTimeMs === 0 && value.length > 0) {
                  this.firstTypeTimeMs = Date.now();
                }
                // 实时上抛给页面暂存:关掉输入条时组件卸载,不上抛内容就没了。
                this.onTextChange(value);
                this.warnIfOverMaxChars();
              })
              .onClick(() => {
                if (this.showEmojiKeyboard) {
                  this.showSystemKeyboard();
                }
              })
          }
        }
        .layoutWeight(1)
        .backgroundColor($r('app.color.immersive_input_field_bg'))
        .borderRadius(8)
        .clip(false)

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          // 条件分支会在面板状态变化时重建图标节点，避免普通成员参数保留旧图片资源。
          if (this.showEmojiKeyboard) {
            FaIconView({
              icon: this.emojiToggleIcon(true),
              color: $r('app.color.icon_secondary'),
              iconSize: 18
            })
          } else {
            FaIconView({
              icon: this.emojiToggleIcon(false),
              color: $r('app.color.icon_secondary'),
              iconSize: 18
            })
          }
        }
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.immersive_input_field_bg'))
        .focusable(false)
        .accessibilityText(this.showEmojiKeyboard ? '切换到键盘' : '选择表情')
        .onClick(() => {
          this.toggleEmojiKeyboard();
        })

        // 回复按钮：圆形、蓝底。提交中显示白色 loading 转圈，否则显示白色 reply 图标。
        // 未达最短字数或提交中时降透明度提示不可用，重复点击由 submit() 内部拦截。
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          if (this.isSubmitting) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color(ON_DARK_FG)
          } else {
            FaIconView({
              icon: this.replyIcon(),
              color: ON_DARK_FG,
              iconSize: 18
            })
          }
        }
        .width(40)
        .height(40)
        .backgroundColor(REPLY_BLUE)
        .opacity(this.canSubmit() ? 1 : 0.5)
        .onClick(() => {
          this.submit();
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      // 键盘弹起：底部内边距只留 8（安全区被键盘遮住）；键盘收起：叠加底部安全区贴 Home 条之上。
      .padding({ left: 12, right: 12, top: 8, bottom: this.activeBottomOffset() > 0 ? 8 : 8 + this.bottomInset })
      // 输入条不是 HDS 组件，无法直接获得标题栏的 systemMaterialEffect。这里在同一个
      // 可见节点上先采样并模糊背后的帖子内容，再叠加主题半透明底色；输入框自身也使用
      // 半透明填充，避免把大部分模糊区域重新盖成实色。
      .backdropBlur(IMMERSIVE_PANEL_BLUR_RADIUS)
      .backgroundColor($r('app.color.immersive_input_bar_bg'))
      .border({
        // 只保留 0.5vp 顶部高光，用于分清输入条与正文；比原来的 1vp 普通分割线更接近
        // HDS 原生按钮的亮边，同时不会在暗色模式下形成一条粗白线。
        width: { top: 0.5 },
        color: $r('app.color.immersive_input_bar_highlight')
      })
      // 一镜到底的源：整条底部输入栏（全宽）与全屏编辑器主面板同 id。放在整条 Row 而非左侧
      // 窄输入框上——宽度本就是满的，生长基本只有竖直方向（从底部整条向上长满全屏），不再从
      // 左下角斜着放大。boost 模式无目标，该 id 无配对、退化为普通渲染，无副作用。
      .geometryTransition(COMPOSER_GEOMETRY_ID, { follow: true })
      // 键盘弹起：整条上移键盘高度，正好贴到键盘上沿；键盘收起：回落到底部。
      // 上移动画由 onAvoidAreaChange 里的 animateTo 驱动（此处不挂 .animation，避免影响图标渲染）。
      .margin({ bottom: this.activeBottomOffset() })
      // 进场时从底部滑入（淡入淡出由根节点统一负责，这里只做位移，避免透明度叠加）。
      .transition(TransitionEffect.move(TransitionEdge.BOTTOM)
        .animation({ duration: 220, curve: Curve.EaseOut }))
      .onAppear(() => {
        this.focusInput();
      })

      if (this.showEmojiKeyboard) {
        EmojiPicker({
          onSelect: (emoji: EmojiItem) => {
            this.insertSelectedEmoji(emoji);
          },
          onDelete: () => {
            this.deleteFromEmojiKeyboard();
          }
        })
          .height(this.emojiPanelHeight + this.bottomInset)
          .padding({ bottom: this.bottomInset })
          .transition(TransitionEffect.move(TransitionEdge.BOTTOM)
            .animation({ duration: 180, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .height('100%')
    // 整层淡入淡出：挂在根节点上，保证组件被 if 挂载/移除时进场与退场都播放动画（遮罩不再突兀）。
    .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }))
    // 扩展到全屏：配合页面切全屏布局，遮罩盖住状态栏、输入条贴到屏幕真实底部。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private replyIcon(): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon('reply');
    return def ? def : { id: 'reply', rawfilePath: 'fa_icons/reply.svg' };
  }

  private emojiToggleIcon(showEmojiKeyboard: boolean): FaIconDefinition {
    const id: string = commentKeyboardToggleIcon(showEmojiKeyboard);
    const def: FaIconDefinition | undefined = getFaIcon(id);
    return def ? def : { id: id, rawfilePath: `fa_icons/${id}.svg` };
  }
}
