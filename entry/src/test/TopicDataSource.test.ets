import { describe, it, expect } from '@ohos/hypium';
import { Topic } from '../main/ets/models/Topic';
import { TopicDataSource } from '../main/ets/services/topic/TopicDataSource';

class RecordingListener implements DataChangeListener {
  reloads: number = 0;
  datasetChanges: number = 0;
  singleAdds: number = 0;

  onDataReloaded(): void {
    this.reloads += 1;
  }

  onDataAdd(index: number): void {
    this.singleAdds += 1;
  }

  onDataAdded(index: number): void {
    this.singleAdds += 1;
  }

  onDataMove(from: number, to: number): void {
  }

  onDataMoved(from: number, to: number): void {
  }

  onDataDelete(index: number): void {
  }

  onDataDeleted(index: number): void {
  }

  onDataChange(index: number): void {
  }

  onDataChanged(index: number): void {
  }

  onDatasetChange(operations: DataOperation[]): void {
    this.datasetChanges += operations.length;
  }
}

function topic(id: number, title: string): Topic {
  const item: Topic = new Topic();
  item.id = id;
  item.title = title;
  return item;
}

export default function topicDataSourceTest() {
  describe('topicDataSourceTest', () => {
    it('reloadsTopicsForRefresh', 0, () => {
      const source: TopicDataSource = new TopicDataSource();
      const listener: RecordingListener = new RecordingListener();
      source.registerDataChangeListener(listener);

      source.reset([topic(1, 'one'), topic(2, 'two')]);

      expect(source.totalCount()).assertEqual(2);
      expect(source.getData(1).title).assertEqual('two');
      expect(listener.reloads).assertEqual(1);
    });

    it('appendsOnlyNewTopicsForPagination', 0, () => {
      const source: TopicDataSource = new TopicDataSource();
      const listener: RecordingListener = new RecordingListener();
      source.registerDataChangeListener(listener);
      source.reset([topic(1, 'one'), topic(2, 'two')]);
      listener.reloads = 0;

      const added: number = source.appendUnique([topic(2, 'two duplicate'), topic(3, 'three')]);

      expect(added).assertEqual(1);
      expect(source.totalCount()).assertEqual(3);
      expect(source.getAll()[2].id).assertEqual(3);
      expect(listener.reloads).assertEqual(1);
    });
  });
}
