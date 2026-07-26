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
