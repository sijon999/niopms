'use client';

import { FormEvent, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import Image from 'next/image';
import { CheckCircle2, Clock3, Loader2, LogOut, Store, UploadCloud, UserRound, XCircle } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { useAuth } from '@/lib/auth-provider';
import { supabase } from '@/lib/supabase/client';

const logoBucket = 'pharmacy-logos';
const maxLogoSize = 2 * 1024 * 1024;
const allowedLogoTypes = ['image/jpeg', 'image/png', 'image/webp'];

export default function ProfilePage() {
  const router = useRouter();
  const { user, profile, pharmacy, membership, loading, isSuperAdmin, refresh, signOut } = useAuth();
  const [saving, setSaving] = useState(false);
  const [logoFile, setLogoFile] = useState<File | null>(null);
  const [form, setForm] = useState({
    ownerName: '',
    ownerPhone: '',
    pharmacyName: '',
    pharmacyEmail: '',
    pharmacyPhone: '',
    addressLine1: '',
    addressLine2: '',
    city: '',
    state: '',
    postalCode: '',
    country: 'Bangladesh',
    license: '',
    taxId: '',
  });

  useEffect(() => {
    if (loading) return;
    if (!user) router.replace('/login');
    else if (isSuperAdmin) router.replace('/admin');
  }, [user, loading, isSuperAdmin, router]);

  useEffect(() => {
    setForm({
      ownerName: profile?.full_name ?? '',
      ownerPhone: profile?.phone ?? '',
      pharmacyName: pharmacy?.name ?? '',
      pharmacyEmail: pharmacy?.email ?? user?.email ?? '',
      pharmacyPhone: pharmacy?.phone ?? '',
      addressLine1: pharmacy?.address_line1 ?? '',
      addressLine2: pharmacy?.address_line2 ?? '',
      city: pharmacy?.city ?? '',
      state: pharmacy?.state ?? '',
      postalCode: pharmacy?.postal_code ?? '',
      country: pharmacy?.country ?? 'Bangladesh',
      license: pharmacy?.drug_license_number ?? '',
      taxId: pharmacy?.tax_id ?? '',
    });
  }, [profile, pharmacy, user]);

  const canEditRegistration = !pharmacy || pharmacy.status === 'rejected';
  const setField = (field: keyof typeof form, value: string) => {
    setForm((current) => ({ ...current, [field]: value }));
  };

  const handleLogoChange = (file: File | undefined) => {
    setLogoFile(null);
    if (!file) return;
    if (!allowedLogoTypes.includes(file.type)) {
      toast.error('Choose a JPG, PNG, or WebP logo.');
      return;
    }
    if (file.size > maxLogoSize) {
      toast.error('The pharmacy logo must be 2 MB or smaller.');
      return;
    }
    setLogoFile(file);
  };

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!user || membership) {
      toast.error('Only an account owner can submit a pharmacy registration.');
      return;
    }
    if (!canEditRegistration) {
      toast.error('This registration cannot be edited while it is under review or approved.');
      return;
    }

    setSaving(true);
    let uploadedPath: string | null = null;
    try {
      if (logoFile) {
        const safeName = logoFile.name.replace(/[^a-zA-Z0-9._-]/g, '_');
        uploadedPath = `${user.id}/${crypto.randomUUID()}-${safeName}`;
        const { error: uploadError } = await supabase.storage
          .from(logoBucket)
          .upload(uploadedPath, logoFile, { contentType: logoFile.type, upsert: false });
        if (uploadError) {
          toast.error(`Could not upload pharmacy logo: ${uploadError.message}`);
          setSaving(false);
          return;
        }
      }

      const { error } = await supabase.rpc('submit_pharmacy_registration', {
        p_owner_name: form.ownerName,
        p_owner_phone: form.ownerPhone,
        p_name: form.pharmacyName,
        p_email: form.pharmacyEmail,
        p_phone: form.pharmacyPhone,
        p_address_line1: form.addressLine1,
        p_address_line2: form.addressLine2 || null,
        p_city: form.city,
        p_state: form.state || null,
        p_postal_code: form.postalCode || null,
        p_country: form.country,
        p_drug_license_number: form.license || null,
        p_tax_id: form.taxId || null,
        p_logo_path: uploadedPath ?? pharmacy?.logo_path ?? null,
      });

      if (error) {
        if (uploadedPath) {
          const { error: cleanupError } = await supabase.storage.from(logoBucket).remove([uploadedPath]);
          if (cleanupError) {
            toast.error(`Registration failed: ${error.message}. Logo cleanup also failed: ${cleanupError.message}`);
            setSaving(false);
            return;
          }
        }
        toast.error(`Could not submit pharmacy registration: ${error.message}`);
        setSaving(false);
        return;
      }

      await refresh();
      setLogoFile(null);
      toast.success(pharmacy ? 'Updated application submitted for review.' : 'Pharmacy registration submitted for review.');
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unexpected registration error.';
      toast.error(message);
    } finally {
      setSaving(false);
    }
  };

  if (loading || !user || isSuperAdmin) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-slate-50">
        <Loader2 className="h-8 w-8 animate-spin text-emerald-600" aria-label="Loading profile" />
      </main>
    );
  }

  if (membership) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-slate-50 p-4">
        <Card className="w-full max-w-lg">
          <CardHeader><CardTitle>Owner profile access required</CardTitle></CardHeader>
          <CardContent className="space-y-4 text-sm text-slate-600">
            <p>Pharmacy registration is available to account owners only. Employee accounts cannot submit or manage owner registrations.</p>
            <Button asChild variant="outline"><Link href="/dashboard">Return to dashboard</Link></Button>
          </CardContent>
        </Card>
      </main>
    );
  }

  const logoUrl = pharmacy?.logo_path
    ? supabase.storage.from(logoBucket).getPublicUrl(pharmacy.logo_path).data.publicUrl
    : null;

  return (
    <main className="min-h-screen bg-slate-50">
      <header className="border-b bg-white">
        <div className="mx-auto flex max-w-5xl items-center justify-between px-4 py-4">
          <div className="flex items-center gap-3">
            <div className="rounded-lg bg-emerald-600 p-2 text-white"><Store className="h-5 w-5" /></div>
            <div><p className="text-sm font-semibold text-emerald-700">NioPOS</p><h1 className="text-xl font-bold">Owner profile</h1></div>
          </div>
          <div className="flex items-center gap-2">
            {pharmacy?.status === 'approved' && <Button asChild variant="outline" size="sm"><Link href="/dashboard">Dashboard</Link></Button>}
            <Button variant="outline" size="sm" onClick={async () => { await signOut(); router.replace('/login'); }}>
              <LogOut className="mr-2 h-4 w-4" /> Sign out
            </Button>
          </div>
        </div>
      </header>

      <div className="mx-auto max-w-5xl space-y-6 px-4 py-8">
        <Card>
          <CardHeader>
            <div className="flex items-center gap-2"><UserRound className="h-5 w-5 text-emerald-600" /><CardTitle>Account information</CardTitle></div>
            <CardDescription>{profile?.email}</CardDescription>
          </CardHeader>
          <CardContent className="text-sm text-slate-600">
            Your account profile is used for pharmacy ownership and registration contact details.
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <div className="flex items-center gap-2"><Store className="h-5 w-5 text-emerald-600" /><CardTitle>Pharmacy Registration</CardTitle></div>
                <CardDescription className="mt-1">Submit pharmacy details for Super Admin review.</CardDescription>
              </div>
              {pharmacy && (
                <span className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-sm font-medium ${
                  pharmacy.status === 'approved' ? 'bg-emerald-100 text-emerald-800' :
                    pharmacy.status === 'pending' ? 'bg-amber-100 text-amber-800' :
                      pharmacy.status === 'rejected' ? 'bg-rose-100 text-rose-800' : 'bg-slate-100 text-slate-700'
                }`}>
                  {pharmacy.status === 'approved' ? <CheckCircle2 className="h-4 w-4" /> :
                    pharmacy.status === 'pending' ? <Clock3 className="h-4 w-4" /> : <XCircle className="h-4 w-4" />}
                  {pharmacy.status.charAt(0).toUpperCase() + pharmacy.status.slice(1)}
                </span>
              )}
            </div>
          </CardHeader>
          <CardContent className="space-y-5">
            {pharmacy?.status === 'pending' && (
              <p className="rounded-md bg-amber-50 p-3 text-sm text-amber-900">Your application is pending review. You can view the submitted information here while it is reviewed.</p>
            )}
            {pharmacy?.status === 'approved' && (
              <p className="rounded-md bg-emerald-50 p-3 text-sm text-emerald-900">Your pharmacy is approved. Registration details are read-only.</p>
            )}
            {pharmacy?.status === 'rejected' && (
              <div className="rounded-md bg-rose-50 p-3 text-sm text-rose-900">
                <p className="font-semibold">Update your application and resubmit.</p>
                <p className="mt-1">{pharmacy.rejection_reason || 'No reason was provided.'}</p>
              </div>
            )}
            {(pharmacy?.status === 'suspended' || pharmacy?.status === 'deactivated') && (
              <p className="rounded-md bg-slate-100 p-3 text-sm text-slate-700">This pharmacy is {pharmacy.status}. Contact support for assistance.</p>
            )}
            {pharmacy?.submitted_at && <p className="text-xs text-slate-500">Submitted {new Date(pharmacy.submitted_at).toLocaleString()}</p>}
            {logoUrl && <Image src={logoUrl} alt="Pharmacy logo" width={64} height={64} unoptimized className="h-16 w-16 rounded border object-contain" />}

            <form onSubmit={handleSubmit} className="space-y-6">
              <fieldset disabled={!canEditRegistration || saving} className="space-y-6 disabled:opacity-75">
                <section className="space-y-4">
                  <h3 className="font-semibold">Owner information</h3>
                  <div className="grid gap-4 sm:grid-cols-2">
                    <div className="space-y-2">
                      <Label htmlFor="ownerName">Owner name <span aria-hidden="true">*</span></Label>
                      <Input id="ownerName" value={form.ownerName} onChange={(event) => setField('ownerName', event.target.value)} required minLength={2} maxLength={120} />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="ownerPhone">Owner phone number <span aria-hidden="true">*</span></Label>
                      <Input id="ownerPhone" type="tel" value={form.ownerPhone} onChange={(event) => setField('ownerPhone', event.target.value)} required minLength={6} maxLength={32} />
                    </div>
                  </div>
                </section>

                <section className="space-y-4">
                  <h3 className="font-semibold">Pharmacy information</h3>
                  <div className="grid gap-4 sm:grid-cols-2">
                    <div className="space-y-2 sm:col-span-2">
                      <Label htmlFor="pharmacyName">Pharmacy name <span aria-hidden="true">*</span></Label>
                      <Input id="pharmacyName" value={form.pharmacyName} onChange={(event) => setField('pharmacyName', event.target.value)} required minLength={2} maxLength={160} />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="pharmacyEmail">Email address <span aria-hidden="true">*</span></Label>
                      <Input id="pharmacyEmail" type="email" value={form.pharmacyEmail} onChange={(event) => setField('pharmacyEmail', event.target.value)} required />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="pharmacyPhone">Phone number <span aria-hidden="true">*</span></Label>
                      <Input id="pharmacyPhone" type="tel" value={form.pharmacyPhone} onChange={(event) => setField('pharmacyPhone', event.target.value)} required minLength={6} maxLength={32} />
                    </div>
                    <div className="space-y-2 sm:col-span-2">
                      <Label htmlFor="addressLine1">Street address <span aria-hidden="true">*</span></Label>
                      <Input id="addressLine1" value={form.addressLine1} onChange={(event) => setField('addressLine1', event.target.value)} required minLength={4} maxLength={240} />
                    </div>
                    <div className="space-y-2 sm:col-span-2">
                      <Label htmlFor="addressLine2">Address line 2</Label>
                      <Input id="addressLine2" value={form.addressLine2} onChange={(event) => setField('addressLine2', event.target.value)} maxLength={240} />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="city">City <span aria-hidden="true">*</span></Label>
                      <Input id="city" value={form.city} onChange={(event) => setField('city', event.target.value)} required minLength={2} maxLength={120} />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="state">State / Province</Label>
                      <Input id="state" value={form.state} onChange={(event) => setField('state', event.target.value)} maxLength={120} />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="postalCode">Postal code</Label>
                      <Input id="postalCode" value={form.postalCode} onChange={(event) => setField('postalCode', event.target.value)} maxLength={32} />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="country">Country <span aria-hidden="true">*</span></Label>
                      <Input id="country" value={form.country} onChange={(event) => setField('country', event.target.value)} required minLength={2} maxLength={120} />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="license">Business / Trade License Number</Label>
                      <Input id="license" value={form.license} onChange={(event) => setField('license', event.target.value)} maxLength={120} />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="taxId">Tax ID</Label>
                      <Input id="taxId" value={form.taxId} onChange={(event) => setField('taxId', event.target.value)} maxLength={120} />
                    </div>
                    <div className="space-y-2 sm:col-span-2">
                      <Label htmlFor="logo">Pharmacy logo (optional; JPG, PNG, or WebP, max 2 MB)</Label>
                      <Input id="logo" type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => handleLogoChange(event.target.files?.[0])} />
                      {logoFile && <p className="text-xs text-slate-500">Selected: {logoFile.name}</p>}
                    </div>
                  </div>
                </section>
              </fieldset>
              {canEditRegistration && (
                <Button type="submit" className="bg-emerald-600 hover:bg-emerald-700" disabled={saving}>
                  {saving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <UploadCloud className="mr-2 h-4 w-4" />}
                  {pharmacy ? 'Resubmit application' : 'Submit pharmacy registration'}
                </Button>
              )}
            </form>
          </CardContent>
        </Card>
      </div>
    </main>
  );
}
