'use client';

import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { Loader2, Pencil, Plus, Search, X } from 'lucide-react';
import { toast } from 'sonner';
import { useAuth, usePermission } from '@/lib/auth-provider';
import { supabase } from '@/lib/supabase/client';
import { Product } from '@/lib/types';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

interface LookupOption {
  id: string;
  name: string;
}

interface ProductForm {
  name: string;
  generic_name: string;
  strength: string;
  category_id: string;
  brand_id: string;
  dosage_form_id: string;
  manufacturer_id: string;
  sku: string;
  barcode: string;
  purchase_price: string;
  selling_price: string;
  wholesale_price: string;
  reorder_level: string;
  requires_prescription: boolean;
}

const emptyForm: ProductForm = {
  name: '',
  generic_name: '',
  strength: '',
  category_id: '',
  brand_id: '',
  dosage_form_id: '',
  manufacturer_id: '',
  sku: '',
  barcode: '',
  purchase_price: '0',
  selling_price: '0',
  wholesale_price: '0',
  reorder_level: '10',
  requires_prescription: false,
};

function ProductLookup({ label, value, options, onChange }: {
  label: string;
  value: string;
  options: LookupOption[];
  onChange: (value: string) => void;
}) {
  return (
    <div className="space-y-2">
      <Label>{label}</Label>
      <select
        value={value}
        onChange={(event) => onChange(event.target.value)}
        className="h-10 w-full rounded-md border border-input bg-background px-3 text-sm"
      >
        <option value="">Not selected</option>
        {options.map((option) => <option key={option.id} value={option.id}>{option.name}</option>)}
      </select>
    </div>
  );
}

export default function ProductsPage() {
  const { pharmacy } = useAuth();
  const canCreate = usePermission('products.create');
  const canEdit = usePermission('products.edit');
  const [products, setProducts] = useState<Product[]>([]);
  const [categories, setCategories] = useState<LookupOption[]>([]);
  const [brands, setBrands] = useState<LookupOption[]>([]);
  const [dosageForms, setDosageForms] = useState<LookupOption[]>([]);
  const [manufacturers, setManufacturers] = useState<LookupOption[]>([]);
  const [form, setForm] = useState<ProductForm>(emptyForm);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [search, setSearch] = useState('');

  const loadData = useCallback(async () => {
    if (!pharmacy) return;
    setLoading(true);
    const [productResult, categoryResult, brandResult, dosageResult, manufacturerResult] = await Promise.all([
      supabase.from('products').select('*').eq('pharmacy_id', pharmacy.id).order('name').limit(500),
      supabase.from('categories').select('id,name').eq('pharmacy_id', pharmacy.id).eq('is_active', true).order('name'),
      supabase.from('brands').select('id,name').eq('pharmacy_id', pharmacy.id).order('name'),
      supabase.from('dosage_forms').select('id,name').eq('pharmacy_id', pharmacy.id).order('name'),
      supabase.from('manufacturers').select('id,name').eq('pharmacy_id', pharmacy.id).order('name'),
    ]);
    const error = productResult.error ?? categoryResult.error ?? brandResult.error ?? dosageResult.error ?? manufacturerResult.error;
    if (error) {
      toast.error(`Could not load medicine catalog: ${error.message}`);
      setLoading(false);
      return;
    }
    setProducts((productResult.data ?? []) as Product[]);
    setCategories(categoryResult.data ?? []);
    setBrands(brandResult.data ?? []);
    setDosageForms(dosageResult.data ?? []);
    setManufacturers(manufacturerResult.data ?? []);
    setLoading(false);
  }, [pharmacy]);

  useEffect(() => { void loadData(); }, [loadData]);

  const visibleProducts = useMemo(() => {
    const query = search.trim().toLowerCase();
    if (!query) return products;
    return products.filter((product) =>
      [product.name, product.generic_name, product.sku, product.barcode]
        .some((value) => value?.toLowerCase().includes(query)),
    );
  }, [products, search]);

  const resetForm = () => {
    setForm(emptyForm);
    setEditingId(null);
  };

  const editProduct = (product: Product) => {
    setEditingId(product.id);
    setForm({
      name: product.name,
      generic_name: product.generic_name ?? '',
      strength: product.strength ?? '',
      category_id: product.category_id ?? '',
      brand_id: product.brand_id ?? '',
      dosage_form_id: product.dosage_form_id ?? '',
      manufacturer_id: product.manufacturer_id ?? '',
      sku: product.sku ?? '',
      barcode: product.barcode ?? '',
      purchase_price: String(product.purchase_price),
      selling_price: String(product.selling_price),
      wholesale_price: String(product.wholesale_price),
      reorder_level: String(product.reorder_level),
      requires_prescription: product.requires_prescription,
    });
  };

  const submitForm = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!pharmacy || (editingId ? !canEdit : !canCreate)) {
      toast.error('You do not have permission to change the medicine catalog.');
      return;
    }
    const purchasePrice = Number(form.purchase_price);
    const sellingPrice = Number(form.selling_price);
    const wholesalePrice = Number(form.wholesale_price);
    const reorderLevel = Number(form.reorder_level);
    if ([purchasePrice, sellingPrice, wholesalePrice, reorderLevel].some((value) => !Number.isFinite(value) || value < 0)) {
      toast.error('Prices and reorder level must be valid non-negative numbers.');
      return;
    }

    const payload = {
      pharmacy_id: pharmacy.id,
      name: form.name.trim(),
      generic_name: form.generic_name.trim() || null,
      strength: form.strength.trim() || null,
      category_id: form.category_id || null,
      brand_id: form.brand_id || null,
      dosage_form_id: form.dosage_form_id || null,
      manufacturer_id: form.manufacturer_id || null,
      sku: form.sku.trim() || null,
      barcode: form.barcode.trim() || null,
      purchase_price: purchasePrice,
      selling_price: sellingPrice,
      wholesale_price: wholesalePrice,
      reorder_level: Math.floor(reorderLevel),
      requires_prescription: form.requires_prescription,
    };

    setSaving(true);
    const result = editingId
      ? await supabase.from('products').update(payload).eq('id', editingId).eq('pharmacy_id', pharmacy.id).select('id').maybeSingle()
      : await supabase.from('products').insert(payload).select('id').maybeSingle();
    if (result.error) {
      toast.error(`Could not save medicine: ${result.error.message}`);
      setSaving(false);
      return;
    }
    if (!result.data) {
      toast.error('No medicine was changed. Check your access and try again.');
      setSaving(false);
      return;
    }
    toast.success(editingId ? 'Medicine updated.' : 'Medicine created.');
    resetForm();
    await loadData();
    setSaving(false);
  };

  const archiveProduct = async (product: Product) => {
    if (!pharmacy || !canEdit) {
      toast.error('You do not have permission to archive medicines.');
      return;
    }
    if (!window.confirm(`Archive ${product.name}? It will remain in history but cannot be sold.`)) return;
    const { error } = await supabase.from('products').update({ status: 'archived' }).eq('id', product.id).eq('pharmacy_id', pharmacy.id);
    if (error) {
      toast.error(`Could not archive medicine: ${error.message}`);
      return;
    }
    toast.success(`${product.name} archived.`);
    await loadData();
  };

  const field = (name: keyof ProductForm, value: string | boolean) => setForm((current) => ({ ...current, [name]: value }));

  return (
    <main className="min-h-screen p-4 sm:p-6 lg:p-8">
      <div className="mx-auto max-w-7xl space-y-6">
        <header className="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h1 className="text-2xl font-bold text-slate-900">Medicines</h1>
            <p className="mt-1 text-sm text-slate-500">Maintain pharmacy products, pricing, identifiers, and reorder levels.</p>
          </div>
          <div className="text-sm text-slate-500">{products.length} medicine{products.length === 1 ? '' : 's'}</div>
        </header>

        {(editingId ? canEdit : canCreate) && (
          <Card>
            <CardHeader>
              <div className="flex items-center justify-between gap-3">
                <div>
                  <CardTitle>{editingId ? 'Edit medicine' : 'Add medicine'}</CardTitle>
                  <CardDescription>Prices and product details apply to this pharmacy only.</CardDescription>
                </div>
                {editingId && <Button type="button" variant="ghost" size="sm" onClick={resetForm}><X className="mr-1 h-4 w-4" /> Cancel edit</Button>}
              </div>
            </CardHeader>
            <CardContent>
              <form onSubmit={submitForm} className="space-y-5">
                <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                  <div className="space-y-2 sm:col-span-2">
                    <Label htmlFor="medicineName">Medicine name *</Label>
                    <Input id="medicineName" value={form.name} onChange={(event) => field('name', event.target.value)} required minLength={2} maxLength={180} />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="genericName">Generic name</Label>
                    <Input id="genericName" value={form.generic_name} onChange={(event) => field('generic_name', event.target.value)} maxLength={180} />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="strength">Strength</Label>
                    <Input id="strength" value={form.strength} onChange={(event) => field('strength', event.target.value)} maxLength={80} placeholder="e.g. 500 mg" />
                  </div>
                  <ProductLookup label="Category" value={form.category_id} options={categories} onChange={(value) => field('category_id', value)} />
                  <ProductLookup label="Brand" value={form.brand_id} options={brands} onChange={(value) => field('brand_id', value)} />
                  <ProductLookup label="Dosage form" value={form.dosage_form_id} options={dosageForms} onChange={(value) => field('dosage_form_id', value)} />
                  <ProductLookup label="Manufacturer" value={form.manufacturer_id} options={manufacturers} onChange={(value) => field('manufacturer_id', value)} />
                  <div className="space-y-2">
                    <Label htmlFor="sku">SKU</Label>
                    <Input id="sku" value={form.sku} onChange={(event) => field('sku', event.target.value)} maxLength={100} />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="barcode">Barcode</Label>
                    <Input id="barcode" value={form.barcode} onChange={(event) => field('barcode', event.target.value)} maxLength={100} inputMode="numeric" />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="purchasePrice">Default purchase price</Label>
                    <Input id="purchasePrice" type="number" step="0.01" min="0" value={form.purchase_price} onChange={(event) => field('purchase_price', event.target.value)} />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="sellingPrice">Default selling price</Label>
                    <Input id="sellingPrice" type="number" step="0.01" min="0" value={form.selling_price} onChange={(event) => field('selling_price', event.target.value)} />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="wholesalePrice">Wholesale price</Label>
                    <Input id="wholesalePrice" type="number" step="0.01" min="0" value={form.wholesale_price} onChange={(event) => field('wholesale_price', event.target.value)} />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="reorderLevel">Reorder level</Label>
                    <Input id="reorderLevel" type="number" min="0" step="1" value={form.reorder_level} onChange={(event) => field('reorder_level', event.target.value)} />
                  </div>
                </div>
                <label className="flex items-center gap-2 text-sm text-slate-700">
                  <input type="checkbox" checked={form.requires_prescription} onChange={(event) => field('requires_prescription', event.target.checked)} />
                  Prescription required
                </label>
                <Button type="submit" className="bg-emerald-600 hover:bg-emerald-700" disabled={saving}>
                  {saving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Plus className="mr-2 h-4 w-4" />}
                  {editingId ? 'Save changes' : 'Add medicine'}
                </Button>
              </form>
            </CardContent>
          </Card>
        )}

        <Card>
          <CardHeader>
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div><CardTitle>Medicine catalog</CardTitle><CardDescription>Search by name, generic, SKU, or barcode.</CardDescription></div>
              <div className="relative w-full sm:max-w-xs">
                <Search className="absolute left-3 top-2.5 h-4 w-4 text-slate-400" />
                <Input className="pl-9" placeholder="Search medicines" value={search} onChange={(event) => setSearch(event.target.value)} />
              </div>
            </div>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="flex justify-center py-12"><Loader2 className="h-6 w-6 animate-spin text-emerald-600" /></div>
            ) : visibleProducts.length === 0 ? (
              <div className="py-12 text-center text-sm text-slate-500">
                {search ? 'No medicines match your search.' : 'No medicines yet. Add your first medicine above.'}
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[860px] text-left text-sm">
                  <thead className="border-b text-xs uppercase text-slate-500">
                    <tr><th className="px-3 py-3">Medicine</th><th className="px-3 py-3">Identifiers</th><th className="px-3 py-3">Prices</th><th className="px-3 py-3">Stock</th><th className="px-3 py-3">Status</th><th className="px-3 py-3">Actions</th></tr>
                  </thead>
                  <tbody className="divide-y">
                    {visibleProducts.map((product) => (
                      <tr key={product.id} className="align-top">
                        <td className="px-3 py-4">
                          <p className="font-medium text-slate-900">{product.name}</p>
                          <p className="text-slate-500">{[product.generic_name, product.strength].filter(Boolean).join(' • ') || 'No generic or strength entered'}</p>
                        </td>
                        <td className="px-3 py-4 text-slate-600"><p>SKU: {product.sku || '—'}</p><p>Barcode: {product.barcode || '—'}</p></td>
                        <td className="px-3 py-4 text-slate-600"><p>Sell: {Number(product.selling_price).toFixed(2)}</p><p>Buy: {Number(product.purchase_price).toFixed(2)}</p></td>
                        <td className="px-3 py-4"><span className={product.total_stock <= product.reorder_level ? 'font-semibold text-amber-700' : 'text-slate-700'}>{product.total_stock}</span><span className="text-slate-500"> / reorder at {product.reorder_level}</span></td>
                        <td className="px-3 py-4">{product.status === 'active' ? 'Active' : 'Archived'}</td>
                        <td className="px-3 py-4">
                          {product.status === 'active' && canEdit && (
                            <div className="flex gap-2">
                              <Button size="sm" variant="outline" onClick={() => editProduct(product)}><Pencil className="mr-1 h-3.5 w-3.5" /> Edit</Button>
                              <Button size="sm" variant="outline" onClick={() => void archiveProduct(product)}>Archive</Button>
                            </div>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </main>
  );
}
