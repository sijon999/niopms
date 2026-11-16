import { useAuth } from '@/lib/auth-provider';

export function usePermissions() {
  const { permissions, isSuperAdmin } = useAuth();

  return {
    can: (key: string) => isSuperAdmin || permissions.includes(key),
    canAny: (keys: string[]) => isSuperAdmin || keys.some((k) => permissions.includes(k)),
    canAll: (keys: string[]) => isSuperAdmin || keys.every((k) => permissions.includes(k)),
  };
}
