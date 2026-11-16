'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { Loader2 } from 'lucide-react';
import { useAuth } from '@/lib/auth-provider';

export default function PendingPage() {
  const router = useRouter();
  const { user, loading } = useAuth();

  useEffect(() => {
    if (!loading) router.replace(user ? '/dashboard/profile' : '/login');
  }, [user, loading, router]);

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-50">
      <Loader2 className="h-8 w-8 animate-spin text-slate-400" aria-label="Opening your profile" />
    </div>
  );
}
