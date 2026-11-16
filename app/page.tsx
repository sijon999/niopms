'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-provider';
import { Loader2 } from 'lucide-react';

export default function LandingPage() {
  const router = useRouter();
  const { user, isSuperAdmin, pharmacy, loading } = useAuth();

  useEffect(() => {
    if (loading) return;
    if (!user) {
      router.replace('/login');
      return;
    }
    if (isSuperAdmin) {
      router.replace('/admin');
      return;
    }
    if (pharmacy?.status === 'approved') {
      router.replace('/dashboard');
    } else {
      router.replace('/dashboard/profile');
    }
  }, [user, isSuperAdmin, pharmacy, loading, router]);

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-50">
      <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
    </div>
  );
}
