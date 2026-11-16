'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useEffect, type ReactNode } from 'react';
import {
  Boxes,
  BarChart3,
  ClipboardList,
  LayoutDashboard,
  LogOut,
  PackageSearch,
  Tags,
  UserRound,
} from 'lucide-react';
import { useAuth, usePermission } from '@/lib/auth-provider';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Loader2 } from 'lucide-react';

const primaryNavigation = [
  { href: '/dashboard', label: 'Dashboard', icon: LayoutDashboard, permission: 'dashboard.view' },
  { href: '/dashboard/products', label: 'Medicines', icon: PackageSearch, permission: 'products.view' },
  { href: '/dashboard/categories', label: 'Categories', icon: Tags, permission: 'categories.view' },
  { href: '/dashboard/inventory', label: 'Inventory & batches', icon: Boxes, permission: 'inventory.view' },
  { href: '/dashboard/profile', label: 'Profile', icon: UserRound, permission: null },
];

const comingSoon = [
  'POS / New Sale',
  'Sales',
  'Purchases',
  'Purchase Returns',
  'Sales Returns',
  'Suppliers',
  'Customers',
  'Expenses',
  'Accounts',
  'Reports',
  'Employees',
  'Roles & Permissions',
  'Notifications',
  'Settings',
];

function NavigationLink({ item }: { item: (typeof primaryNavigation)[number] }) {
  const pathname = usePathname();
  const hasPermission = usePermission(item.permission ?? 'dashboard.view');
  const permitted = item.permission === null || hasPermission;
  const active = pathname === item.href || (item.href !== '/dashboard' && pathname.startsWith(`${item.href}/`));
  const Icon = item.icon;

  return (
    <Link
      href={item.href}
      aria-current={active ? 'page' : undefined}
      className={`flex items-center gap-3 rounded-md px-3 py-2 text-sm transition-colors ${
        active ? 'bg-emerald-50 font-medium text-emerald-800' : 'text-slate-600 hover:bg-slate-100'
      } ${!permitted ? 'pointer-events-none opacity-50' : ''}`}
      aria-disabled={!permitted}
    >
      <Icon className="h-4 w-4" />
      {item.label}
    </Link>
  );
}

export default function DashboardLayout({ children }: { children: ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const { user, profile, pharmacy, loading, isSuperAdmin, signOut } = useAuth();

  useEffect(() => {
    if (loading) return;
    if (!user) router.replace('/login');
    else if (isSuperAdmin) router.replace('/admin');
    else if (pharmacy?.status !== 'approved' && pathname !== '/dashboard/profile') router.replace('/dashboard/profile');
  }, [user, pharmacy, loading, isSuperAdmin, pathname, router]);

  if (loading || !user || isSuperAdmin || (pharmacy?.status !== 'approved' && pathname !== '/dashboard/profile')) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-slate-50">
        <Loader2 className="h-8 w-8 animate-spin text-emerald-600" aria-label="Loading pharmacy dashboard" />
      </main>
    );
  }

  return (
    <div className="min-h-screen bg-slate-50 lg:flex">
      <aside className="border-b bg-white lg:min-h-screen lg:w-64 lg:shrink-0 lg:border-b-0 lg:border-r">
        <div className="flex items-center justify-between px-4 py-4 lg:block lg:px-5">
          <Link href="/dashboard" className="text-sm font-bold text-emerald-700">NioPOS</Link>
          <p className="max-w-[65%] truncate text-sm font-medium text-slate-700 lg:mt-2 lg:max-w-full">
            {pharmacy?.name ?? 'Pharmacy profile'}
          </p>
        </div>
        <nav aria-label="Owner dashboard" className="flex gap-1 overflow-x-auto px-3 pb-3 lg:block lg:space-y-1">
          {primaryNavigation.map((item) => <NavigationLink key={item.href} item={item} />)}
        </nav>
        <div className="hidden px-5 pb-3 pt-4 text-xs font-semibold uppercase tracking-wide text-slate-400 lg:block">
          Other modules
        </div>
        <div className="hidden space-y-1 px-3 pb-4 lg:block">
          {comingSoon.map((label) => (
            <div key={label} className="flex items-center gap-3 rounded-md px-3 py-2 text-sm text-slate-400" title="This module is not implemented yet">
              <ClipboardList className="h-4 w-4" />
              <span>{label}</span>
            </div>
          ))}
        </div>
        <div className="hidden px-3 pb-5 lg:block">
          <Card className="border-dashed bg-slate-50 p-3 text-xs text-slate-500">
            <BarChart3 className="mb-2 h-4 w-4 text-emerald-700" />
            More workflows are being added in phases.
          </Card>
          <Button
            variant="ghost"
            className="mt-3 w-full justify-start text-slate-600"
            onClick={async () => { await signOut(); router.replace('/login'); }}
          >
            <LogOut className="mr-2 h-4 w-4" /> Sign out
          </Button>
          <p className="mt-2 truncate px-3 text-xs text-slate-400">{profile?.email}</p>
        </div>
      </aside>
      <div className="min-w-0 flex-1">{children}</div>
    </div>
  );
}
