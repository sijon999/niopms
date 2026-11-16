'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { Boxes, Loader2, PackageSearch, Tags } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { useAuth, usePermission } from '@/lib/auth-provider';
import { supabase } from '@/lib/supabase/client';

interface DashboardMetrics {
  activeProducts: number | null;
  batchCount: number | null;
  expiredBatches: number | null;
  expiringBatches: number | null;
}

const initialMetrics: DashboardMetrics = {
  activeProducts: null,
  batchCount: null,
  expiredBatches: null,
  expiringBatches: null,
};

export default function DashboardPage() {
  const router = useRouter();
  const { user, profile, pharmacy, loading, isSuperAdmin } = useAuth();
  const canViewProducts = usePermission('products.view');
  const canViewInventory = usePermission('inventory.view');
  const [metrics, setMetrics] = useState(initialMetrics);
  const [metricsLoading, setMetricsLoading] = useState(true);

  useEffect(() => {
    if (loading) return;
    if (!user) router.replace('/login');
    else if (isSuperAdmin) router.replace('/admin');
    else if (pharmacy?.status !== 'approved') router.replace('/dashboard/profile');
  }, [user, pharmacy, loading, isSuperAdmin, router]);

  const loadMetrics = useCallback(async () => {
    if (!pharmacy || pharmacy.status !== 'approved') return;
    setMetricsLoading(true);
    const today = new Date().toISOString().slice(0, 10);
    const expiryCutoffDate = new Date();
    expiryCutoffDate.setDate(expiryCutoffDate.getDate() + 30);
    const expiryCutoff = expiryCutoffDate.toISOString().slice(0, 10);

    const [productResult, batchResult, expiredResult, expiringResult] = await Promise.all([
      canViewProducts
        ? supabase.from('products').select('id', { count: 'exact', head: true }).eq('pharmacy_id', pharmacy.id).eq('status', 'active')
        : Promise.resolve(null),
      canViewInventory
        ? supabase.from('product_batches').select('id', { count: 'exact', head: true }).eq('pharmacy_id', pharmacy.id)
        : Promise.resolve(null),
      canViewInventory
        ? supabase.from('product_batches').select('id', { count: 'exact', head: true }).eq('pharmacy_id', pharmacy.id).gt('available_qty', 0).lt('expiry_date', today)
        : Promise.resolve(null),
      canViewInventory
        ? supabase.from('product_batches').select('id', { count: 'exact', head: true }).eq('pharmacy_id', pharmacy.id).gt('available_qty', 0).gte('expiry_date', today).lte('expiry_date', expiryCutoff)
        : Promise.resolve(null),
    ]);

    const errors = [productResult, batchResult, expiredResult, expiringResult]
      .filter((result) => result && result.error)
      .map((result) => result?.error?.message);
    if (errors.length) toast.error(`Could not load all dashboard metrics: ${errors.join('; ')}`);

    setMetrics({
      activeProducts: productResult && !productResult.error ? productResult.count ?? 0 : null,
      batchCount: batchResult && !batchResult.error ? batchResult.count ?? 0 : null,
      expiredBatches: expiredResult && !expiredResult.error ? expiredResult.count ?? 0 : null,
      expiringBatches: expiringResult && !expiringResult.error ? expiringResult.count ?? 0 : null,
    });
    setMetricsLoading(false);
  }, [pharmacy, canViewProducts, canViewInventory]);

  useEffect(() => { void loadMetrics(); }, [loadMetrics]);

  if (loading || !user || !pharmacy || pharmacy.status !== 'approved') {
    return (
      <main className="flex min-h-screen items-center justify-center bg-slate-50">
        <Loader2 className="h-8 w-8 animate-spin text-emerald-600" aria-label="Loading dashboard" />
      </main>
    );
  }

  const cards = [
    { title: 'Active medicines', value: metrics.activeProducts, access: canViewProducts, href: '/dashboard/products', icon: PackageSearch },
    { title: 'Inventory batches', value: metrics.batchCount, access: canViewInventory, href: '/dashboard/inventory', icon: Boxes },
    { title: 'Expired batches with stock', value: metrics.expiredBatches, access: canViewInventory, href: '/dashboard/inventory', icon: Boxes },
    { title: 'Batches expiring in 30 days', value: metrics.expiringBatches, access: canViewInventory, href: '/dashboard/inventory', icon: Boxes },
  ];

  return (
    <main className="min-h-screen p-4 sm:p-6 lg:p-8">
      <div className="mx-auto max-w-7xl space-y-6">
        <header className="flex flex-wrap items-end justify-between gap-3">
          <div>
            <p className="text-sm font-semibold text-emerald-700">NioPOS</p>
            <h1 className="text-2xl font-bold text-slate-900">{pharmacy.name}</h1>
            <p className="mt-1 text-sm text-slate-500">Welcome, {profile?.full_name || profile?.email}.</p>
          </div>
          <Button variant="outline" onClick={() => void loadMetrics()} disabled={metricsLoading}>
            {metricsLoading ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null} Refresh metrics
          </Button>
        </header>

        <section aria-label="Pharmacy metrics" className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          {cards.map(({ title, value, access, href, icon: Icon }) => (
            <Card key={title}>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardDescription>{title}</CardDescription>
                <Icon className="h-4 w-4 text-emerald-700" />
              </CardHeader>
              <CardContent>
                <p className="text-2xl font-bold text-slate-900">
                  {metricsLoading ? '…' : !access ? '—' : value === null ? 'Error' : value.toLocaleString()}
                </p>
                {access && <Link className="mt-2 inline-block text-xs text-emerald-700 hover:underline" href={href}>View details</Link>}
                {!access && <p className="mt-2 text-xs text-slate-500">Permission required</p>}
              </CardContent>
            </Card>
          ))}
        </section>

        <section className="grid gap-4 md:grid-cols-3">
          <Card><CardHeader><CardTitle className="flex items-center gap-2 text-base"><PackageSearch className="h-4 w-4 text-emerald-700" /> Medicines</CardTitle><CardDescription>Manage product details, pricing, and reorder levels.</CardDescription></CardHeader><CardContent><Button asChild variant="outline" size="sm"><Link href="/dashboard/products">Open catalog</Link></Button></CardContent></Card>
          <Card><CardHeader><CardTitle className="flex items-center gap-2 text-base"><Tags className="h-4 w-4 text-emerald-700" /> Categories</CardTitle><CardDescription>Organize your medicine catalog.</CardDescription></CardHeader><CardContent><Button asChild variant="outline" size="sm"><Link href="/dashboard/categories">Manage categories</Link></Button></CardContent></Card>
          <Card><CardHeader><CardTitle className="flex items-center gap-2 text-base"><Boxes className="h-4 w-4 text-emerald-700" /> Inventory</CardTitle><CardDescription>Review batch expiry and record auditable stock changes.</CardDescription></CardHeader><CardContent><Button asChild variant="outline" size="sm"><Link href="/dashboard/inventory">Open inventory</Link></Button></CardContent></Card>
        </section>
      </div>
    </main>
  );
}
