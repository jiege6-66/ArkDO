import { Topic } from '../../models/Topic';

// 首页主题列表懒加载数据源。刷新/分页后通知 LazyForEach 重新读取数据；
// LazyForEach 仍只创建视口附近列表项，避免多页主题行全部常驻成组件树。
export class TopicDataSource implements IDataSource {
  private topics: Topic[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.topics.length;
  }

  getData(index: number): Topic {
    return this.topics[index];
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

  getAll(): Topic[] {
    return this.topics;
  }

  reset(topics: Topic[]): void {
    this.topics = topics.slice();
    for (let index: number = 0; index < this.listeners.length; index++) {
      this.listeners[index].onDataReloaded();
    }
  }

  appendUnique(nextTopics: Topic[]): number {
    const fresh: Topic[] = this.collectFresh(nextTopics);
    if (fresh.length === 0) {
      return 0;
    }
    const startIndex: number = this.topics.length;
    this.topics = this.topics.concat(fresh);
    for (let i: number = 0; i < fresh.length; i++) {
      for (let j: number = 0; j < this.listeners.length; j++) {
        this.listeners[j].onDataAdd(startIndex + i);
      }
    }
    return fresh.length;
  }

  prependOrReplace(nextTopics: Topic[]): number {
    const incoming: Topic[] = [];
    const incomingIds: Set<number> = new Set<number>();
    for (let index: number = 0; index < nextTopics.length; index++) {
      const topic: Topic = nextTopics[index];
      if (incomingIds.has(topic.id)) {
        continue;
      }
      incomingIds.add(topic.id);
      incoming.push(topic);
    }
    if (incoming.length === 0) {
      return 0;
    }

    const remaining: Topic[] = [];
    for (let index: number = 0; index < this.topics.length; index++) {
      if (!incomingIds.has(this.topics[index].id)) {
        remaining.push(this.topics[index]);
      }
    }
    this.topics = incoming.concat(remaining);
    this.notifyReload();
    return incoming.length;
  }

  private collectFresh(nextTopics: Topic[]): Topic[] {
    const seenIds: Set<number> = new Set();
    for (let index: number = 0; index < this.topics.length; index++) {
      seenIds.add(this.topics[index].id);
    }
    const fresh: Topic[] = [];
    for (let index: number = 0; index < nextTopics.length; index++) {
      const topic: Topic = nextTopics[index];
      if (!seenIds.has(topic.id)) {
        seenIds.add(topic.id);
        fresh.push(topic);
      }
    }
    return fresh;
  }

  private notifyReload(): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}
