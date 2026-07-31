import { TopicCategory } from '../../models/Topic';
import { CategoryIndex } from '../site/CategoryIndex';

export interface HomeIncomingTopicsState {
  topicIds: number[];
  messageIds: number[];
}

export function createHomeIncomingTopicsState(): HomeIncomingTopicsState {
  return { topicIds: [], messageIds: [] };
}

export function homeIncomingTopicsCount(state: HomeIncomingTopicsState): number {
  return state.topicIds.length;
}

export function clearHomeIncomingTopics(_state: HomeIncomingTopicsState): HomeIncomingTopicsState {
  return createHomeIncomingTopicsState();
}

export function snapshotHomeIncomingTopics(state: HomeIncomingTopicsState): HomeIncomingTopicsState {
  return { topicIds: state.topicIds.slice(), messageIds: state.messageIds.slice() };
}

export function removeIncomingTopicsSnapshot(
  state: HomeIncomingTopicsState,
  snapshot: HomeIncomingTopicsState
): HomeIncomingTopicsState {
  const remainingTopicIds: number[] = [];
  const remainingMessageIds: number[] = [];
  for (let index: number = 0; index < state.topicIds.length; index++) {
    const topicId: number = state.topicIds[index];
    const snapshotIndex: number = snapshot.topicIds.indexOf(topicId);
    const unchangedSinceSnapshot: boolean = snapshotIndex >= 0 &&
      snapshot.messageIds[snapshotIndex] === state.messageIds[index];
    if (!unchangedSinceSnapshot) {
      remainingTopicIds.push(topicId);
      remainingMessageIds.push(state.messageIds[index]);
    }
  }
  return { topicIds: remainingTopicIds, messageIds: remainingMessageIds };
}

export function addIncomingTopicId(state: HomeIncomingTopicsState, topicId: number): HomeIncomingTopicsState {
  return addIncomingTopicMessage(state, topicId, 0);
}

export function addIncomingTopicMessage(
  state: HomeIncomingTopicsState,
  topicId: number,
  messageId: number
): HomeIncomingTopicsState {
  if (!Number.isFinite(topicId) || topicId <= 0) {
    return state;
  }
  const normalizedId: number = Math.floor(topicId);
  const normalizedMessageId: number = Number.isFinite(messageId) ? Math.max(0, Math.floor(messageId)) : 0;
  const existingIndex: number = state.topicIds.indexOf(normalizedId);
  if (existingIndex >= 0) {
    if (normalizedMessageId <= state.messageIds[existingIndex]) {
      return state;
    }
    const updatedMessageIds: number[] = state.messageIds.slice();
    updatedMessageIds[existingIndex] = normalizedMessageId;
    return { topicIds: state.topicIds.slice(), messageIds: updatedMessageIds };
  }
  const nextIds: number[] = state.topicIds.slice();
  const nextMessageIds: number[] = state.messageIds.slice();
  nextIds.push(normalizedId);
  nextMessageIds.push(normalizedMessageId);
  return { topicIds: nextIds, messageIds: nextMessageIds };
}

export function nextDebugIncomingTopicId(state: HomeIncomingTopicsState): number {
  return 100001 + state.topicIds.length;
}

/**
 * 这条 /latest 消息算不算「当前列表的新话题」——版块维度的闸。
 *
 * MessageBus 的频道是全局的,不随筛选条件变(见 topic_tracking_state.rb:35-40 那几个常量),
 * 所以限定了版块时必须自己拿 payload.category_id 比一次。规则对齐官方前端的 notifyIncoming:
 *  · 没限定版块 → 照单全收
 *  · 消息版块 == 当前版块 → 收
 *  · 消息版块的父版块 == 当前版块 → 也收(看父版块时,子版块的新帖同样会出现在列表里)
 *  · 认不出消息属于哪个版块 → 不收。限定了版块却来路不明,宁可漏报也别把外版块的帖子插进来。
 */
export function incomingTopicMatchesCategory(
  categories: TopicCategory[],
  scope: TopicCategory | undefined,
  categoryId: number | undefined
): boolean {
  if (scope === undefined) {
    return true;
  }
  if (categoryId === undefined) {
    return false;
  }
  if (categoryId === scope.id) {
    return true;
  }
  const parent: TopicCategory | undefined = CategoryIndex.findParent(categories, categoryId);
  return parent !== undefined && parent.id === scope.id;
}
