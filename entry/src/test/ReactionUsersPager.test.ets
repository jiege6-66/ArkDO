import { describe, it, expect } from '@ohos/hypium';
import { ReactionUsersPager } from '../main/ets/services/topic/ReactionUsersPager';

export default function reactionUsersPagerTest() {
  describe('reactionUsersPagerTest', () => {
    it('deduplicatesPagesAndFiltersByReaction', 0, () => {
      const pager: ReactionUsersPager = new ReactionUsersPager();

      pager.append({
        totalRows: 3,
        users: [
          { id: 1, username: 'alice', reaction: 'heart' },
          { id: 1, username: 'alice', reaction: 'heart' },
          { id: 2, username: 'bob', reaction: '+1' }
        ]
      });

      expect(pager.allUsers().length).assertEqual(2);
      expect(pager.usersFor('heart').length).assertEqual(1);
      expect(pager.usersFor('+1')[0].username).assertEqual('bob');
      expect(pager.hasMore()).assertTrue();
    });

    it('stopsLoadingAfterAllUsersAreCollected', 0, () => {
      const pager: ReactionUsersPager = new ReactionUsersPager();
      pager.append({
        totalRows: 2,
        users: [
          { id: 1, username: 'alice', reaction: 'heart' },
          { id: 2, username: 'bob', reaction: '+1' }
        ]
      });

      expect(pager.hasMore()).assertFalse();
    });
  });
}
