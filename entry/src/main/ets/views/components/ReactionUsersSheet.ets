import { PostReaction, ReactionUser } from '../../models/TopicDetail';
import { getReactionEmoji } from './EmojiRegistry';
import { UserAvatar } from './UserAvatar';

interface VisibleReaction {
  id: string;
  count: number;
  icon: Resource;
}

// 帖子反应用户的原生底部弹层。请求和分页状态由详情页持有，这里只渲染与发出交互事件。
@Component
export struct ReactionUsersSheet {
  @Prop reactions: PostReaction[] = [];
  @Prop totalRows: number = 0;
  @Prop users: ReactionUser[] = [];
  @Prop selectedReaction: string = '';
  @Prop isInitialLoading: boolean = false;
  @Prop isLoadingMore: boolean = false;
  @Prop hasMore: boolean = false;
  @Prop initialError: string = '';
  @Prop loadMoreError: string = '';
  onSelectReaction: (reaction: string) => void = () => {};
  onLoadMore: () => void = () => {};
  onRetryInitial: () => void = () => {};
  onRetryLoadMore: () => void = () => {};
  onOpenUser: (user: ReactionUser) => void = () => {};

  build() {
    Column() {
      Text('表情回应')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ left: 20, right: 20, top: 8, bottom: 12 })

      Scroll() {
        Row({ space: 8 }) {
          this.ReactionFilter('', this.totalRows)
          ForEach(this.visibleReactions(), (reaction: VisibleReaction) => {
            this.ReactionFilter(reaction.id, reaction.count, reaction.icon)
          }, (reaction: VisibleReaction) => reaction.id)
        }
        .padding({ left: 20, right: 20, bottom: 12 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      Divider()
        .strokeWidth(1)
        .color($r('app.color.border'))

      if (this.isInitialLoading && this.users.length === 0) {
        this.InitialLoading()
      } else if (this.initialError.length > 0 && this.users.length === 0) {
        this.InitialError()
      } else if (this.users.length === 0 && !this.hasMore) {
        this.EmptyState()
      } else if (this.filteredUsers().length === 0) {
        this.FilteredEmptyState()
      } else {
        Scroll() {
          Column() {
            ForEach(this.filteredUsers(), (user: ReactionUser) => {
              this.UserRow(user)
            }, (user: ReactionUser) => `${user.id}:${user.reaction}`)

            this.LoadFooter()
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        // 少量用户时也固定从弹层内容区顶部开始，不让 Scroll 的剩余空间把列表视觉居中。
        .align(Alignment.Top)
        .onReachEnd(() => {
          if (this.hasMore && !this.isLoadingMore) {
            this.onLoadMore();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: 12 })
  }

  @Builder
  private ReactionFilter(reaction: string, count: number, icon?: Resource) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 5 }) {
        if (icon !== undefined) {
          Image(icon)
            .width(18)
            .height(18)
            .objectFit(ImageFit.Contain)
            .draggable(false)
        } else {
          Text('所有')
            .fontSize(14)
            .fontColor(this.filterTextColor(reaction))
        }
        Text(`${count}`)
          .fontSize(14)
          .fontWeight(reaction === this.selectedReaction ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.filterTextColor(reaction))
      }
    }
    .height(34)
    .padding({ left: 12, right: 12 })
    .backgroundColor(reaction === this.selectedReaction ? $r('app.color.brand') : $r('app.color.surface_card'))
    .border({ width: 1, color: reaction === this.selectedReaction ? $r('app.color.brand') : $r('app.color.border') })
    .borderRadius(17)
    .onClick(() => {
      this.onSelectReaction(reaction);
    })
  }

  @Builder
  private UserRow(user: ReactionUser) {
    Row({ space: 12 }) {
      UserAvatar({ user: user, avatarSize: 42 })

      Column({ space: 2 }) {
        Text(this.displayName(user))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`@${user.username}`)
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.reactionIcon(user.reaction) !== undefined) {
        Image(this.reactionIcon(user.reaction) as Resource)
          .width(24)
          .height(24)
          .objectFit(ImageFit.Contain)
          .draggable(false)
      }
    }
    .width('100%')
    .height(68)
    .padding({ left: 20, right: 20 })
    .onClick(() => {
      this.onOpenUser(user);
    })
  }

  @Builder
  private InitialLoading() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(24)
        .height(24)
        .color($r('app.color.brand'))
      Text('正在加载表情回应')
        .fontSize(14)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private InitialError() {
    Column({ space: 12 }) {
      Text(this.initialError)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .maxLines(2)
      Button('重试')
        .fontSize(14)
        .fontColor($r('app.color.brand'))
        .backgroundColor($r('app.color.surface_card'))
        .border({ width: 1, color: $r('app.color.border') })
        .borderRadius(6)
        .onClick(() => {
          this.onRetryInitial();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }

  @Builder
  private EmptyState() {
    Text('暂无表情回应')
      .fontSize(14)
      .fontColor($r('app.color.text_tertiary'))
      .width('100%')
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .padding({ top: 36 })
  }

  // 某个分类可能只出现在尚未读取的后续页；空列表时提供显式入口，避免没有可滚动内容而触不了底。
  @Builder
  private FilteredEmptyState() {
    Column({ space: 12 }) {
      Text('当前已加载的回应中没有此表情')
        .fontSize(14)
        .fontColor($r('app.color.text_tertiary'))
      if (this.hasMore) {
        Button('继续加载')
          .fontSize(14)
          .fontColor($r('app.color.brand'))
          .backgroundColor($r('app.color.surface_card'))
          .border({ width: 1, color: $r('app.color.border') })
          .borderRadius(6)
          .onClick(() => {
            this.onLoadMore();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(24)
  }

  @Builder
  private LoadFooter() {
    if (this.isLoadingMore) {
      Row({ space: 8 }) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color($r('app.color.brand'))
        Text('正在加载更多')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .height(54)
      .justifyContent(FlexAlign.Center)
    } else if (this.loadMoreError.length > 0) {
      Button('加载失败，点击重试')
        .fontSize(13)
        .fontColor($r('app.color.brand'))
        .width('100%')
        .height(54)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onRetryLoadMore();
        })
    } else if (this.hasMore) {
      // 选中的分类可能在下一页暂时没有命中；保留显式入口，不能只依赖 Scroll 的重复触底回调。
      Button('继续加载')
        .fontSize(13)
        .fontColor($r('app.color.brand'))
        .width('100%')
        .height(54)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onLoadMore();
        })
    } else if (!this.hasMore) {
      Text('已加载全部表情回应')
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .height(54)
        .textAlign(TextAlign.Center)
    }
  }

  private visibleReactions(): VisibleReaction[] {
    const result: VisibleReaction[] = [];
    for (let index: number = 0; index < this.reactions.length; index++) {
      const reaction: PostReaction = this.reactions[index];
      const icon: Resource | undefined = getReactionEmoji(reaction.id);
      if (reaction.count > 0 && icon !== undefined) {
        result.push({ id: reaction.id, count: reaction.count, icon: icon });
      }
    }
    return result;
  }

  private filteredUsers(): ReactionUser[] {
    if (this.selectedReaction.length === 0) {
      return this.users;
    }
    return this.users.filter((user: ReactionUser) => user.reaction === this.selectedReaction);
  }

  private reactionIcon(reaction: string): Resource | undefined {
    return getReactionEmoji(reaction);
  }

  private displayName(user: ReactionUser): string {
    return user.displayName && user.displayName.length > 0 ? user.displayName : user.username;
  }

  private filterTextColor(reaction: string): ResourceColor {
    return reaction === this.selectedReaction ? Color.White : $r('app.color.text_secondary');
  }
}
