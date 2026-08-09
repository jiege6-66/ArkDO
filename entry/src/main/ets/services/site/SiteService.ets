import { TopicCategory, TopicTag } from '../../models/Topic';
import { ChallengeState, JsonNetworkClient, NetworkResult } from '../network/NetworkTypes';
import { forwardFailure, unexpectedResponse } from '../network/NetworkResults';

interface DiscourseSiteResponse {
  categories?: DiscourseCategory[];
  // 站点热门标签。Discourse 在 /site.json 里直接给,匿名可见 —— 抽屉的「常用标签」用它,
  // 既不必额外发请求,也不受 /tags/filter/search 的 max_tag_search_results 上限约束。
  top_tags?: DiscourseTopTag[];
}

interface DiscourseTopTag {
  id?: number;
  name?: string;
  slug?: string;
}

interface DiscourseCategory {
  id?: number;
  name?: string;
  color?: string;
  text_color?: string;
  slug?: string;
  parent_category_id?: number;
  uploaded_logo?: string | DiscourseUploadedLogo;
  icon?: string;
  read_restricted?: boolean;
}

interface DiscourseUploadedLogo {
  url?: string;
}

export interface SiteMetadata {
  categories: TopicCategory[];
  /** 站点热门标签(按热度排)。站点没开标签功能时为空数组。 */
  topTags: TopicTag[];
}

export class SiteService {
  private bridge: JsonNetworkClient;

  constructor(bridge: JsonNetworkClient) {
    this.bridge = bridge;
  }

  async getSiteMetadata(): Promise<NetworkResult<SiteMetadata>> {
    const response: NetworkResult<string> = await this.bridge.getJson('/site.json');
    if (!response.success) {
      return this.forwardFailure<SiteMetadata>(response);
    }

    if (response.data === undefined) {
      return this.unexpectedResponse<SiteMetadata>(response.statusCode, response.challengeState, '站点信息响应为空。');
    }

    try {
      const payload: DiscourseSiteResponse = JSON.parse(response.data) as DiscourseSiteResponse;
      if (!payload.categories) {
        return this.unexpectedResponse<SiteMetadata>(response.statusCode, response.challengeState, '站点信息响应缺少 categories。');
      }

      return {
        success: true,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        data: {
          categories: this.mapCategories(payload.categories),
          topTags: this.mapTopTags(payload.top_tags)
        }
      };
    } catch (error) {
      return this.unexpectedResponse<SiteMetadata>(response.statusCode, response.challengeState, '站点信息响应不是有效 JSON。');
    }
  }

  // 站点没开标签功能时 /site.json 里没有 top_tags,返回空数组即可 —— 抽屉据此显示空态。
  private mapTopTags(sourceTags?: DiscourseTopTag[]): TopicTag[] {
    const tags: TopicTag[] = [];
    if (!sourceTags) {
      return tags;
    }
    for (let index: number = 0; index < sourceTags.length; index++) {
      const raw: DiscourseTopTag = sourceTags[index];
      if (typeof raw.name !== 'string' || raw.name.length === 0) {
        continue;
      }
      tags.push({ id: raw.id, name: raw.name, slug: raw.slug });
    }
    return tags;
  }

  private mapCategories(sourceCategories: DiscourseCategory[]): TopicCategory[] {
    const categories: TopicCategory[] = [];
    for (let index: number = 0; index < sourceCategories.length; index++) {
      const category: TopicCategory | undefined = this.mapCategory(sourceCategories[index]);
      if (category) {
        categories.push(category);
      }
    }
    return categories;
  }

  private mapCategory(sourceCategory: DiscourseCategory): TopicCategory | undefined {
    if (typeof sourceCategory.id !== 'number' || typeof sourceCategory.name !== 'string') {
      return undefined;
    }

    const category: TopicCategory = {
      id: sourceCategory.id,
      name: sourceCategory.name,
      color: this.normalizeHex(sourceCategory.color, '6B7280'),
      textColor: this.normalizeHex(sourceCategory.text_color, 'FFFFFF')
    };

    if (sourceCategory.slug && sourceCategory.slug.length > 0) {
      category.slug = sourceCategory.slug;
    }
    if (typeof sourceCategory.parent_category_id === 'number') {
      category.parentCategoryId = sourceCategory.parent_category_id;
    }
    const uploadedLogo: string = this.mapUploadedLogo(sourceCategory.uploaded_logo);
    if (uploadedLogo.length > 0) {
      category.uploadedLogo = uploadedLogo;
    }
    if (sourceCategory.icon && sourceCategory.icon.length > 0) {
      category.icon = sourceCategory.icon;
    }
    if (typeof sourceCategory.read_restricted === 'boolean') {
      category.readRestricted = sourceCategory.read_restricted;
    }
    return category;
  }

  private mapUploadedLogo(uploadedLogo?: string | DiscourseUploadedLogo): string {
    if (!uploadedLogo) {
      return '';
    }
    if (typeof uploadedLogo === 'string') {
      return uploadedLogo.trim();
    }
    if (uploadedLogo.url && uploadedLogo.url.length > 0) {
      return uploadedLogo.url;
    }
    return '';
  }

  private normalizeHex(value: string | undefined, fallback: string): string {
    if (!value) {
      return fallback;
    }
    const normalized: string = value.replace('#', '').trim();
    return normalized.length > 0 ? normalized : fallback;
  }

  private forwardFailure<T>(response: NetworkResult<string>): NetworkResult<T> {
    return forwardFailure<T>(response);
  }

  private unexpectedResponse<T>(statusCode: number, challengeState: ChallengeState, message: string): NetworkResult<T> {
    return unexpectedResponse<T>(statusCode, challengeState, message);
  }
}
