'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase/client';
import { useAuth } from '@/lib/auth-provider';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent } from '@/components/ui/card';
import { Loader2, Pill, User } from 'lucide-react';
import { toast } from 'sonner';

export default function SignupPage() {
  const router = useRouter();
  const { refresh } = useAuth();
  const [loading, setLoading] = useState(false);
  const [fullName, setFullName] = useState('');
  const [phone, setPhone] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (password.length < 8) {
      toast.error('Password must be at least 8 characters');
      return;
    }

    setLoading(true);
    const { data, error } = await supabase.auth.signUp({
      email: email.trim(),
      password,
      options: { data: { full_name: fullName.trim(), phone: phone.trim() } },
    });

    if (error) {
      toast.error(error.message);
      setLoading(false);
      return;
    }
    if (!data.user) {
      toast.error('Account creation failed. Please try again.');
      setLoading(false);
      return;
    }

    if (data.session) {
      await refresh();
      toast.success('Account created. You can register your pharmacy from your profile.');
      router.replace('/dashboard/profile');
    } else {
      toast.success('Account created. Verify your email, then sign in to continue.');
      router.replace('/login');
    }
    setLoading(false);
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-slate-50 via-white to-emerald-50/30 px-4 py-8">
      <div className="w-full max-w-lg">
        <div className="mb-8 flex flex-col items-center text-center">
          <div className="mb-3 flex h-12 w-12 items-center justify-center rounded-xl bg-emerald-600">
            <Pill className="h-6 w-6 text-white" />
          </div>
          <h1 className="text-2xl font-bold tracking-tight">Create your account</h1>
          <p className="mt-1 text-sm text-slate-500">Register a user account to get started with NioPOS.</p>
        </div>

        <Card className="shadow-lg">
          <CardContent className="p-6">
            <form onSubmit={handleSubmit} className="space-y-5">
              <div className="flex items-center gap-2">
                <User className="h-5 w-5 text-emerald-600" />
                <h2 className="text-lg font-semibold">Account information</h2>
              </div>
              <div className="space-y-2">
                <Label htmlFor="fullName">Full name <span aria-hidden="true">*</span></Label>
                <Input id="fullName" autoComplete="name" value={fullName} onChange={(event) => setFullName(event.target.value)} required minLength={2} maxLength={120} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="phone">Phone number <span aria-hidden="true">*</span></Label>
                <Input id="phone" type="tel" autoComplete="tel" value={phone} onChange={(event) => setPhone(event.target.value)} required minLength={6} maxLength={32} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="email">Email address <span aria-hidden="true">*</span></Label>
                <Input id="email" type="email" autoComplete="email" value={email} onChange={(event) => setEmail(event.target.value)} required />
              </div>
              <div className="space-y-2">
                <Label htmlFor="password">Password <span aria-hidden="true">*</span></Label>
                <Input id="password" type="password" autoComplete="new-password" value={password} onChange={(event) => setPassword(event.target.value)} required minLength={8} />
              </div>
              <Button type="submit" className="w-full bg-emerald-600 hover:bg-emerald-700" disabled={loading}>
                {loading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                Create account
              </Button>
              <p className="text-center text-sm text-slate-500">
                Already have an account?{' '}
                <Link href="/login" className="font-medium text-emerald-600 hover:underline">Sign in</Link>
              </p>
            </form>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
