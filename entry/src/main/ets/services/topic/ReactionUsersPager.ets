import { ReactionUser, ReactionUsersPage } from '../../models/TopicDetail';

// 反应用户分页状态的纯逻辑。页面只需镜像 allUsers 的数组供 ArkUI 响应式渲染。
export class ReactionUsersPager {
  private users: ReactionUser[] = [];
  private seenKeys: Set<string> = new Set<string>();
  private totalRows: number = 0;

  reset(): void {
    this.users = [];
    this.seenKeys.clear();
    this.totalRows = 0;
  }

  append(page: ReactionUsersPage): void {
    this.totalRows = Math.max(0, page.totalRows);
    for (let index: number = 0; index < page.users.length; index++) {
      const user: ReactionUser = page.users[index];
      const key: string = `${user.id}:${user.reaction}`;
      if (this.seenKeys.has(key)) {
        continue;
      }
      this.seenKeys.add(key);
      this.users.push(user);
    }
  }

  allUsers(): ReactionUser[] {
    return this.users.slice();
  }

  usersFor(reaction?: string): ReactionUser[] {
    if (reaction === undefined) {
      return this.allUsers();
    }
    return this.users.filter((user: ReactionUser) => user.reaction === reaction);
  }

  hasMore(): boolean {
    return this.users.length < this.totalRows;
  }
}
