'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { CheckCircle2, Clock3, Loader2, LogOut, ShieldAlert, Store, XCircle } from 'lucide-react';
import Image from 'next/image';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Textarea } from '@/components/ui/textarea';
import { useAuth } from '@/lib/auth-provider';
import { supabase } from '@/lib/supabase/client';
import { PharmacyStatus } from '@/lib/types';

interface AdminPharmacy {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  city: string | null;
  country: string;
  status: PharmacyStatus;
  created_at: string;
  submitted_at: string;
  approved_at: string | null;
  owner_id: string | null;
  rejection_reason: string | null;
  logo_path: string | null;
  drug_license_number: string | null;
  address_line1: string | null;
  address_line2: string | null;
  postal_code: string | null;
  state: string | null;
  owner?: { full_name: string | null; email: string; phone: string | null } | null;
}

type StatusFilter = 'all' | PharmacyStatus;
type StatusCounts = Record<StatusFilter, number>;

const emptyCounts: StatusCounts = {
  all: 0,
  pending: 0,
  approved: 0,
  rejected: 0,
  suspended: 0,
  deactivated: 0,
};

const statusLabels: Record<PharmacyStatus, string> = {
  pending: 'Pending review',
  approved: 'Approved',
  rejected: 'Rejected',
  suspended: 'Suspended',
  deactivated: 'Deactivated',
};

export default function AdminPage() {
  const router = useRouter();
  const { user, profile, loading: authLoading, isSuperAdmin, signOut } = useAuth();
  const [pharmacies, setPharmacies] = useState<AdminPharmacy[]>([]);
  const [counts, setCounts] = useState<StatusCounts>(emptyCounts);
  const [filter, setFilter] = useState<StatusFilter>('all');
  const [loading, setLoading] = useState(true);
  const [updatingId, setUpdatingId] = useState<string | null>(null);
  const [rejectionReasons, setRejectionReasons] = useState<Record<string, string>>({});

  const loadPharmacies = useCallback(async () => {
    setLoading(true);
    const [list, all, pending, approved, rejected, suspended, deactivated] = await Promise.all([
      supabase
        .from('pharmacies')
        .select('id, name, email, phone, city, state, postal_code, country, address_line1, address_line2, drug_license_number, logo_path, status, created_at, submitted_at, approved_at, owner_id, rejection_reason')
        .order('submitted_at', { ascending: false })
        .limit(100),
      supabase.from('pharmacies').select('id', { count: 'exact', head: true }),
      supabase.from('pharmacies').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
      supabase.from('pharmacies').select('id', { count: 'exact', head: true }).eq('status', 'approved'),
      supabase.from('pharmacies').select('id', { count: 'exact', head: true }).eq('status', 'rejected'),
      supabase.from('pharmacies').select('id', { count: 'exact', head: true }).eq('status', 'suspended'),
      supabase.from('pharmacies').select('id', { count: 'exact', head: true }).eq('status', 'deactivated'),
    ]);

    const error = list.error ?? all.error ?? pending.error ?? approved.error ?? rejected.error ?? suspended.error ?? deactivated.error;
    if (error) {
      toast.error(`Could not load pharmacy records: ${error.message}`);
      setLoading(false);
      return;
    }

    const ownerIds = Array.from(new Set((list.data ?? []).map((pharmacy) => pharmacy.owner_id).filter((id): id is string => Boolean(id))));
    const owners = ownerIds.length
      ? await supabase.from('app_users').select('id, full_name, email, phone').in('id', ownerIds)
      : { data: [], error: null };
    if (owners.error) {
      toast.error(`Could not load pharmacy owner details: ${owners.error.message}`);
      setLoading(false);
      return;
    }

    const ownersById = new Map((owners.data ?? []).map((owner) => [owner.id, owner]));
    setPharmacies((list.data ?? []).map((pharmacy) => ({
      ...pharmacy,
      owner: pharmacy.owner_id ? ownersById.get(pharmacy.owner_id) ?? null : null,
    })) as AdminPharmacy[]);
    setCounts({
      all: all.count ?? 0,
      pending: pending.count ?? 0,
      approved: approved.count ?? 0,
      rejected: rejected.count ?? 0,
      suspended: suspended.count ?? 0,
      deactivated: deactivated.count ?? 0,
    });
    setLoading(false);
  }, []);

  useEffect(() => {
    if (authLoading) return;
    if (!user) {
      router.replace('/login');
      return;
    }
    if (isSuperAdmin) void loadPharmacies();
  }, [authLoading, user, isSuperAdmin, loadPharmacies, router]);

  const visiblePharmacies = useMemo(
    () => (filter === 'all' ? pharmacies : pharmacies.filter((pharmacy) => pharmacy.status === filter)),
    [filter, pharmacies],
  );

  const changeStatus = async (pharmacy: AdminPharmacy, status: PharmacyStatus) => {
    if (!user || !isSuperAdmin) {
      toast.error('Super Admin access is required.');
      return;
    }

    const rejectionReason = rejectionReasons[pharmacy.id]?.trim() ?? '';
    if (status === 'rejected' && rejectionReason.length < 5) {
      toast.error('Enter a rejection reason of at least 5 characters.');
      return;
    }

    setUpdatingId(pharmacy.id);
    const now = new Date().toISOString();
    const update = status === 'approved'
      ? {
          status,
          approved_at: pharmacy.approved_at ?? now,
          approved_by: user.id,
          suspended_at: null,
          deactivated_at: null,
          rejection_reason: null,
        }
      : status === 'rejected'
        ? {
            status,
            rejection_reason: rejectionReason,
            approved_at: null,
            approved_by: null,
            suspended_at: null,
            deactivated_at: null,
          }
      : status === 'suspended'
        ? { status, suspended_at: now }
        : { status, deactivated_at: now };
    const { data, error } = await supabase
      .from('pharmacies')
      .update(update)
      .eq('id', pharmacy.id)
      .select('id')
      .maybeSingle();

    if (error) {
      toast.error(`Could not update ${pharmacy.name}: ${error.message}`);
      setUpdatingId(null);
      return;
    }
    if (!data) {
      toast.error('The update was not authorized or the pharmacy no longer exists.');
      setUpdatingId(null);
      return;
    }

    toast.success(`${pharmacy.name}: ${statusLabels[status].toLowerCase()}.`);
    await loadPharmacies();
    setUpdatingId(null);
  };

  if (authLoading || (user && isSuperAdmin && loading)) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-slate-50">
        <Loader2 className="h-8 w-8 animate-spin text-emerald-600" aria-label="Loading Super Admin dashboard" />
      </main>
    );
  }

  if (!user || !profile || !isSuperAdmin) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-slate-50 p-4">
        <Card className="w-full max-w-md">
          <CardContent className="flex flex-col items-center gap-3 p-8 text-center">
            <ShieldAlert className="h-10 w-10 text-rose-600" />
            <h1 className="text-xl font-semibold">Super Admin access required</h1>
            <p className="text-sm text-slate-600">This account is not authorized to manage pharmacies.</p>
            <Button variant="outline" onClick={() => router.replace('/')}>Return to home</Button>
          </CardContent>
        </Card>
      </main>
    );
  }

  const filters: { key: StatusFilter; label: string }[] = [
    { key: 'all', label: 'All pharmacies' },
    { key: 'pending', label: 'Pending' },
    { key: 'approved', label: 'Approved' },
    { key: 'rejected', label: 'Rejected' },
    { key: 'suspended', label: 'Suspended' },
    { key: 'deactivated', label: 'Deactivated' },
  ];

  return (
    <main className="min-h-screen bg-slate-50">
      <header className="border-b bg-white">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-4 py-4 sm:px-6 lg:px-8">
          <div className="flex items-center gap-3">
            <div className="rounded-lg bg-emerald-600 p-2 text-white"><Store className="h-5 w-5" /></div>
            <div>
              <p className="text-sm font-semibold text-emerald-700">NioPOS</p>
              <h1 className="text-xl font-bold text-slate-900">Super Admin</h1>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <span className="hidden text-sm text-slate-600 sm:inline">{profile.email}</span>
            <Button variant="outline" size="sm" onClick={async () => { await signOut(); router.replace('/login'); }}>
              <LogOut className="mr-2 h-4 w-4" /> Sign out
            </Button>
          </div>
        </div>
      </header>

      <div className="mx-auto max-w-7xl space-y-8 px-4 py-8 sm:px-6 lg:px-8">
        <section>
          <h2 className="text-2xl font-bold text-slate-900">Pharmacy management</h2>
          <p className="mt-1 text-sm text-slate-600">Review registrations and manage pharmacy access.</p>
        </section>

        <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6" aria-label="Pharmacy status totals">
          {filters.map(({ key, label }) => (
            <button key={key} type="button" onClick={() => setFilter(key)} className="text-left">
              <Card className={filter === key ? 'border-emerald-500 ring-1 ring-emerald-500' : 'hover:border-slate-300'}>
                <CardContent className="p-5">
                  <p className="text-sm text-slate-500">{label}</p>
                  <p className="mt-2 text-3xl font-semibold text-slate-900">{counts[key]}</p>
                </CardContent>
              </Card>
            </button>
          ))}
        </section>

        <Card>
          <CardHeader>
            <div className="flex items-center justify-between gap-4">
              <CardTitle>{filter === 'all' ? 'Recent pharmacies' : `${statusLabels[filter]} pharmacies`}</CardTitle>
              <Button variant="outline" size="sm" onClick={() => void loadPharmacies()} disabled={loading}>
                Refresh
              </Button>
            </div>
          </CardHeader>
          <CardContent>
            {visiblePharmacies.length === 0 ? (
              <div className="flex flex-col items-center gap-2 py-12 text-center text-slate-500">
                <Store className="h-8 w-8" />
                <p>No pharmacies found in this view.</p>
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[900px] text-left text-sm">
                  <thead className="border-b text-xs uppercase text-slate-500">
                    <tr>
                      <th className="px-3 py-3 font-medium">Pharmacy</th>
                      <th className="px-3 py-3 font-medium">Contact</th>
                      <th className="px-3 py-3 font-medium">Owner</th>
                      <th className="px-3 py-3 font-medium">Submitted</th>
                      <th className="px-3 py-3 font-medium">Status</th>
                      <th className="px-3 py-3 font-medium">Actions</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y">
                    {visiblePharmacies.map((pharmacy) => (
                      <tr key={pharmacy.id} className="align-top">
                        <td className="px-3 py-4">
                          {pharmacy.logo_path && (
                            <Image
                              src={supabase.storage.from('pharmacy-logos').getPublicUrl(pharmacy.logo_path).data.publicUrl}
                              alt={`${pharmacy.name} logo`}
                              width={48}
                              height={48}
                              unoptimized
                              className="mb-2 h-12 w-12 rounded border object-contain"
                            />
                          )}
                          <p className="font-medium text-slate-900">{pharmacy.name}</p>
                          <p className="text-slate-500">
                            {[pharmacy.address_line1, pharmacy.address_line2, pharmacy.city, pharmacy.state, pharmacy.postal_code, pharmacy.country].filter(Boolean).join(', ')}
                          </p>
                        </td>
                        <td className="px-3 py-4">
                          <p>{pharmacy.email}</p>
                          <p className="text-slate-500">{pharmacy.phone || 'No phone provided'}</p>
                          {pharmacy.drug_license_number && <p className="mt-1 text-xs text-slate-500">License: {pharmacy.drug_license_number}</p>}
                        </td>
                        <td className="px-3 py-4">
                          <p className="font-medium">{pharmacy.owner?.full_name || 'Owner profile unavailable'}</p>
                          <p className="text-slate-500">{pharmacy.owner?.email || '—'}</p>
                          <p className="text-slate-500">{pharmacy.owner?.phone || 'No phone provided'}</p>
                        </td>
                        <td className="whitespace-nowrap px-3 py-4 text-slate-600">
                          {new Date(pharmacy.submitted_at).toLocaleString()}
                        </td>
                        <td className="px-3 py-4">
                          <span className="inline-flex items-center gap-1.5 rounded-full bg-slate-100 px-2.5 py-1 text-xs font-medium text-slate-700">
                            {pharmacy.status === 'approved' ? <CheckCircle2 className="h-3.5 w-3.5 text-emerald-600" /> :
                              pharmacy.status === 'pending' ? <Clock3 className="h-3.5 w-3.5 text-amber-600" /> :
                                <XCircle className="h-3.5 w-3.5 text-rose-600" />}
                            {statusLabels[pharmacy.status]}
                          </span>
                          {pharmacy.status === 'rejected' && pharmacy.rejection_reason && (
                            <p className="mt-2 max-w-xs text-xs text-rose-700">Reason: {pharmacy.rejection_reason}</p>
                          )}
                        </td>
                        <td className="px-3 py-4">
                          <div className="flex flex-wrap gap-2">
                            {pharmacy.status === 'pending' && (
                              <Button size="sm" onClick={() => void changeStatus(pharmacy, 'approved')} disabled={updatingId === pharmacy.id}>
                                {updatingId === pharmacy.id ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Approve'}
                              </Button>
                            )}
                            {pharmacy.status === 'pending' && (
                              <div className="w-full space-y-2">
                                <Textarea
                                  aria-label={`Rejection reason for ${pharmacy.name}`}
                                  placeholder="Explain what needs to be corrected"
                                  value={rejectionReasons[pharmacy.id] ?? ''}
                                  onChange={(event) => setRejectionReasons((current) => ({ ...current, [pharmacy.id]: event.target.value }))}
                                  maxLength={1000}
                                />
                                <Button size="sm" variant="destructive" onClick={() => void changeStatus(pharmacy, 'rejected')} disabled={updatingId === pharmacy.id}>
                                  Reject application
                                </Button>
                              </div>
                            )}
                            {pharmacy.status === 'rejected' && (
                              <Button size="sm" onClick={() => void changeStatus(pharmacy, 'approved')} disabled={updatingId === pharmacy.id}>
                                Approve
                              </Button>
                            )}
                            {(pharmacy.status === 'suspended' || pharmacy.status === 'deactivated') && (
                              <Button size="sm" onClick={() => void changeStatus(pharmacy, 'approved')} disabled={updatingId === pharmacy.id}>
                                Reactivate
                              </Button>
                            )}
                            {pharmacy.status === 'approved' && (
                              <>
                                <Button size="sm" variant="outline" onClick={() => void changeStatus(pharmacy, 'suspended')} disabled={updatingId === pharmacy.id}>
                                  Suspend
                                </Button>
                                <Button size="sm" variant="destructive" onClick={() => void changeStatus(pharmacy, 'deactivated')} disabled={updatingId === pharmacy.id}>
                                  Deactivate
                                </Button>
                              </>
                            )}
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                {counts.all > pharmacies.length && (
                  <p className="pt-4 text-center text-xs text-slate-500">
                    Showing the 100 most recently registered pharmacies.
                  </p>
                )}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </main>
  );
}
