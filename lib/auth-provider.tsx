'use client';

import { createContext, useCallback, useContext, useEffect, useState, ReactNode } from 'react';
import { Session, User } from '@supabase/supabase-js';
import { supabase } from '@/lib/supabase/client';
import { AppUser, Pharmacy, Role, PharmacyMember } from '@/lib/types';
import { toast } from 'sonner';

interface AuthContextValue {
  session: Session | null;
  user: User | null;
  profile: AppUser | null;
  pharmacy: Pharmacy | null;
  membership: PharmacyMember | null;
  role: Role | null;
  permissions: string[];
  loading: boolean;
  isSuperAdmin: boolean;
  signOut: () => Promise<void>;
  refresh: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue>({
  session: null,
  user: null,
  profile: null,
  pharmacy: null,
  membership: null,
  role: null,
  permissions: [],
  loading: true,
  isSuperAdmin: false,
  signOut: async () => {},
  refresh: async () => {},
});

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<AppUser | null>(null);
  const [pharmacy, setPharmacy] = useState<Pharmacy | null>(null);
  const [membership, setMembership] = useState<PharmacyMember | null>(null);
  const [role, setRole] = useState<Role | null>(null);
  const [permissions, setPermissions] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);

  const clearPharmacyState = useCallback(() => {
    setPharmacy(null);
    setMembership(null);
    setRole(null);
    setPermissions([]);
  }, []);

  const loadProfile = useCallback(async (uid: string) => {
    const { data, error } = await supabase.from('app_users').select('*').eq('id', uid).maybeSingle();
    if (error) throw new Error(`Could not load your account profile: ${error.message}`);
    if (!data) throw new Error('Your account profile is missing. Please contact support.');
    const result = data as AppUser;
    setProfile(result);
    return result;
  }, []);

  const loadPharmacyData = useCallback(async (uid: string) => {
    const { data: ownPharmacy, error: ownerError } = await supabase
      .from('pharmacies')
      .select('*')
      .eq('owner_id', uid)
      .maybeSingle();
    if (ownerError) throw new Error(`Could not load your pharmacy registration: ${ownerError.message}`);

    if (ownPharmacy) {
      setPharmacy(ownPharmacy as Pharmacy);
      setMembership(null);
      setRole(null);
      const { data: allPerms, error: permissionsError } = await supabase.from('permissions').select('key');
      if (permissionsError) throw new Error(`Could not load pharmacy permissions: ${permissionsError.message}`);
      setPermissions((allPerms ?? []).map((permission) => permission.key));
      return;
    }

    const { data: member, error: membershipError } = await supabase
      .from('pharmacy_members')
      .select('*, role:roles(*)')
      .eq('user_id', uid)
      .eq('is_active', true)
      .maybeSingle();
    if (membershipError) throw new Error(`Could not load your pharmacy membership: ${membershipError.message}`);

    if (!member) {
      clearPharmacyState();
      return;
    }

    const currentMember = member as PharmacyMember;
    setMembership(currentMember);
    setRole(currentMember.role ?? null);
    const { data: memberPharmacy, error: pharmacyError } = await supabase
      .from('pharmacies')
      .select('*')
      .eq('id', currentMember.pharmacy_id)
      .maybeSingle();
    if (pharmacyError) throw new Error(`Could not load your pharmacy: ${pharmacyError.message}`);
    setPharmacy(memberPharmacy as Pharmacy | null);

    const { data: rolePermissions, error: rolePermissionsError } = await supabase
      .from('role_permissions')
      .select('permission:permissions(key)')
      .eq('role_id', currentMember.role_id);
    if (rolePermissionsError) throw new Error(`Could not load your role permissions: ${rolePermissionsError.message}`);
    setPermissions(
      (rolePermissions ?? [])
        .map((item) => {
          const permission = item.permission as { key: string } | { key: string }[] | null;
          return Array.isArray(permission) ? permission[0]?.key : permission?.key;
        })
        .filter((key): key is string => Boolean(key)),
    );
  }, [clearPharmacyState]);

  const hydrateSession = useCallback(async (currentSession: Session | null) => {
    setSession(currentSession);
    setUser(currentSession?.user ?? null);
    try {
      if (!currentSession?.user) {
        setProfile(null);
        clearPharmacyState();
        return;
      }

      const currentProfile = await loadProfile(currentSession.user.id);
      if (currentProfile.is_super_admin) {
        clearPharmacyState();
      } else {
        await loadPharmacyData(currentSession.user.id);
      }
    } catch (error) {
      setProfile(null);
      clearPharmacyState();
      const message = error instanceof Error ? error.message : 'Could not load account data.';
      console.error('Account data loading failed', error);
      toast.error(message);
    } finally {
      setLoading(false);
    }
  }, [clearPharmacyState, loadPharmacyData, loadProfile]);

  const refresh = useCallback(async () => {
    const { data, error } = await supabase.auth.getSession();
    if (error) {
      console.error('Session lookup failed', error);
      toast.error(`Could not check your session: ${error.message}`);
      setLoading(false);
      return;
    }
    await hydrateSession(data.session);
  }, [hydrateSession]);

  useEffect(() => {
    void refresh();
    let active = true;
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, currentSession) => {
      queueMicrotask(() => {
        if (active) void hydrateSession(currentSession);
      });
    });

    return () => {
      active = false;
      subscription.unsubscribe();
    };
  }, [hydrateSession, refresh]);

  const signOut = useCallback(async () => {
    const { error } = await supabase.auth.signOut();
    if (error) {
      toast.error(`Could not sign out: ${error.message}`);
      return;
    }
    await hydrateSession(null);
  }, [hydrateSession]);

  return (
    <AuthContext.Provider
      value={{
        session,
        user,
        profile,
        pharmacy,
        membership,
        role,
        permissions,
        loading,
        isSuperAdmin: profile?.is_super_admin ?? false,
        signOut,
        refresh,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}

export function usePermission(key: string) {
  const { permissions, isSuperAdmin } = useAuth();
  return isSuperAdmin || permissions.includes(key);
}
