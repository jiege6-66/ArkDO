import { describe, it, expect, afterEach } from '@ohos/hypium';
import { LoginGate } from '../main/ets/services/session/LoginGate';
import { SiteUploadSettings } from '../main/ets/services/site/SiteSettingsService';
import { UploadService } from '../main/ets/services/upload/UploadService';

/**
 * 上传白名单与身份的关系。
 *
 * 这组用例守的是一条容易反复踩的约定:**身份未查到时按宽松处理,由服务端裁决**。
 * 它已经在 LoginGate.canUploadAttachment 里写过一次,但抽 allowedExtensions 时被写反了 ——
 * staffValue 初值是 false,于是版主在会话检查落地前(以及那次检查因撞盾/离线失败时的整个会话)
 * 会被当成普通用户,选择器里看不到自己真能传的后缀,直传还会收到「本站不允许上传 .xxx 文件」。
 */

function settings(exts: string[], staffExts: string[]): SiteUploadSettings {
  return {
    maxImageSizeKb: 10240,
    maxAttachmentSizeKb: 10240,
    authorizedExtensions: exts,
    authorizedExtensionsForStaff: staffExts,
    newuserMaxAttachments: 0,
    newuserMaxEmbeddedMedia: 5
  };
}

export default function uploadPermissionsTest() {
  describe('UploadPermissions', () => {
    afterEach(() => {
      LoginGate.clearUserPrivileges();
    });

    it('excludes staff-only extensions for a confirmed regular user', 0, () => {
      // 等级已查到(TL1)且非 staff:staff 专属后缀不该出现。
      LoginGate.setUserPrivileges(1, false);
      const result: string[] = UploadService.nonImageExtensions(settings(['zip', 'png'], ['exe']));
      expect(result.includes('zip')).assertTrue();
      expect(result.includes('exe')).assertFalse();
    });

    it('includes staff-only extensions for staff', 0, () => {
      LoginGate.setUserPrivileges(4, true);
      const result: string[] = UploadService.nonImageExtensions(settings(['zip', 'png'], ['exe']));
      expect(result.includes('exe')).assertTrue();
    });

    it('includes staff-only extensions while privileges are still unknown', 0, () => {
      // 会话检查还没回来(或失败了):此时 isStaff() 恒为 false,但不能因此把功能藏掉。
      // 与 LoginGate.canUploadAttachment 的「等级未知一律放行」同一条约定。
      LoginGate.clearUserPrivileges();
      const result: string[] = UploadService.nonImageExtensions(settings(['zip', 'png'], ['exe']));
      expect(result.includes('exe')).assertTrue();
    });

    it('drops image extensions from the file picker list', 0, () => {
      LoginGate.setUserPrivileges(1, false);
      const result: string[] = UploadService.nonImageExtensions(settings(['zip', 'png', 'jpg'], []));
      expect(result.includes('png')).assertFalse();
      expect(result.includes('jpg')).assertFalse();
      expect(result.includes('zip')).assertTrue();
    });

    it('canUploadAttachment stays permissive when trust level is unknown', 0, () => {
      // 与上面那条同源:这里顺带把既有约定钉住,免得日后有人"顺手"把它改严。
      LoginGate.clearUserPrivileges();
      expect(LoginGate.canUploadAttachment(0)).assertTrue();
      LoginGate.setUserPrivileges(0, false);
      expect(LoginGate.canUploadAttachment(0)).assertFalse();
      expect(LoginGate.canUploadAttachment(2)).assertTrue();
    });
  });
}
