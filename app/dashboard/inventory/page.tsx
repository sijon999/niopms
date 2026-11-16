'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';
import { Loader2, Plus, RefreshCw } from 'lucide-react';
import { toast } from 'sonner';
import { useAuth, usePermission } from '@/lib/auth-provider';
import { supabase } from '@/lib/supabase/client';
import { InventoryMovement, Product, ProductBatch, Supplier } from '@/lib/types';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

interface BatchRow extends ProductBatch {
  products: { name: string; sku: string | null };
  suppliers: { name: string } | null;
}

interface MovementRow extends InventoryMovement {
  products: { name: string };
  product_batches: { batch_number: string } | null;
}

function firstRelation<T>(value: T | T[] | null): T | null {
  return Array.isArray(value) ? value[0] ?? null : value;
}

interface BatchForm {
  product_id: string;
  batch_number: string;
  expiry_date: string;
  manufacturing_date: string;
  quantity: string;
  purchase_price: string;
  selling_price: string;
  mrp: string;
  supplier_id: string;
  reason: string;
}

const blankBatch: BatchForm = {
  product_id: '',
  batch_number: '',
  expiry_date: '',
  manufacturing_date: '',
  quantity: '',
  purchase_price: '0',
  selling_price: '0',
  mrp: '0',
  supplier_id: '',
  reason: 'Opening stock',
};

function dateInputMinimum() {
  const date = new Date();
  date.setDate(date.getDate() + 1);
  return date.toISOString().slice(0, 10);
}

export default function InventoryPage() {
  const { pharmacy } = useAuth();
  const canAdjust = usePermission('inventory.adjust');
  const [batches, setBatches] = useState<BatchRow[]>([]);
  const [movements, setMovements] = useState<MovementRow[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [suppliers, setSuppliers] = useState<Supplier[]>([]);
  const [form, setForm] = useState<BatchForm>(blankBatch);
  const [adjustBatchId, setAdjustBatchId] = useState('');
  const [adjustQuantity, setAdjustQuantity] = useState('');
  const [adjustReason, setAdjustReason] = useState('');
  const [adjustReference, setAdjustReference] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const loadData = useCallback(async () => {
    if (!pharmacy) return;
    setLoading(true);
    const [batchResult, movementResult, productResult, supplierResult] = await Promise.all([
      supabase.from('product_batches').select('*,products!inner(name,sku),suppliers(name)').eq('pharmacy_id', pharmacy.id).order('expiry_date').limit(500),
      supabase.from('inventory_movements').select('id,product_id,batch_id,pharmacy_id,movement_type,quantity_delta,reference_type,reference_id,created_by,note,created_at,products!inner(name),product_batches(batch_number)').eq('pharmacy_id', pharmacy.id).order('created_at', { ascending: false }).limit(100),
      supabase.from('products').select('*').eq('pharmacy_id', pharmacy.id).eq('status', 'active').order('name').limit(500),
      supabase.from('suppliers').select('*').eq('pharmacy_id', pharmacy.id).eq('is_active', true).order('name').limit(500),
    ]);
    const error = batchResult.error ?? movementResult.error ?? productResult.error ?? supplierResult.error;
    if (error) {
      toast.error(`Could not load inventory: ${error.message}`);
      setLoading(false);
      return;
    }
    setBatches((batchResult.data ?? []).map((row) => ({
      ...row,
      products: firstRelation(row.products) ?? { name: 'Unknown medicine', sku: null },
      suppliers: firstRelation(row.suppliers),
    })));
    setMovements((movementResult.data ?? []).map((row) => ({
      ...row,
      products: firstRelation(row.products) ?? { name: 'Unknown medicine' },
      product_batches: firstRelation(row.product_batches),
    })));
    setProducts((productResult.data ?? []) as Product[]);
    setSuppliers((supplierResult.data ?? []) as Supplier[]);
    setLoading(false);
  }, [pharmacy]);

  useEffect(() => { void loadData(); }, [loadData]);

  const setBatchField = (key: keyof BatchForm, value: string) => setForm((current) => ({ ...current, [key]: value }));

  const createBatch = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!pharmacy || !canAdjust) {
      toast.error('Inventory adjustment permission is required.');
      return;
    }
    const quantity = Number(form.quantity);
    const purchasePrice = Number(form.purchase_price);
    const sellingPrice = Number(form.selling_price);
    const mrp = Number(form.mrp);
    if (!Number.isInteger(quantity) || quantity <= 0 || [purchasePrice, sellingPrice, mrp].some((value) => !Number.isFinite(value) || value < 0)) {
      toast.error('Enter a positive whole-number quantity and valid non-negative prices.');
      return;
    }
    if (form.reason.trim().length < 5) {
      toast.error('Please provide a reason of at least 5 characters.');
      return;
    }
    setSaving(true);
    const { data, error } = await supabase.rpc('create_inventory_batch', {
      p_pharmacy_id: pharmacy.id,
      p_product_id: form.product_id,
      p_batch_number: form.batch_number.trim(),
      p_expiry_date: form.expiry_date,
      p_quantity: quantity,
      p_purchase_price: purchasePrice,
      p_selling_price: sellingPrice,
      p_mrp: mrp,
      p_manufacturing_date: form.manufacturing_date || null,
      p_supplier_id: form.supplier_id || null,
      p_reason: form.reason.trim(),
    });
    if (error) {
      toast.error(`Could not add opening stock: ${error.message}`);
      setSaving(false);
      return;
    }
    if (!data) {
      toast.error('The inventory batch was not created.');
      setSaving(false);
      return;
    }
    toast.success('Opening stock batch created.');
    setForm(blankBatch);
    await loadData();
    setSaving(false);
  };

  const adjustStock = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!pharmacy || !canAdjust) {
      toast.error('Inventory adjustment permission is required.');
      return;
    }
    const quantityDelta = Number(adjustQuantity);
    if (!Number.isInteger(quantityDelta) || quantityDelta === 0 || adjustReason.trim().length < 5) {
      toast.error('Enter a non-zero whole-number adjustment and a reason of at least 5 characters.');
      return;
    }
    const selectedBatch = batches.find((batch) => batch.id === adjustBatchId);
    if (!selectedBatch) {
      toast.error('Select a batch from this pharmacy.');
      return;
    }
    if (!window.confirm(`Apply ${quantityDelta > 0 ? '+' : ''}${quantityDelta} units to ${selectedBatch.products.name} / ${selectedBatch.batch_number}?`)) return;
    setSaving(true);
    const { data, error } = await supabase.rpc('adjust_inventory_batch', {
      p_pharmacy_id: pharmacy.id,
      p_batch_id: selectedBatch.id,
      p_quantity_delta: quantityDelta,
      p_reason: adjustReason.trim(),
      p_reference: adjustReference.trim() || null,
    });
    if (error) {
      toast.error(`Could not adjust stock: ${error.message}`);
      setSaving(false);
      return;
    }
    if (!data) {
      toast.error('The stock adjustment was not recorded.');
      setSaving(false);
      return;
    }
    toast.success('Stock adjustment recorded in the inventory ledger.');
    setAdjustQuantity('');
    setAdjustReason('');
    setAdjustReference('');
    await loadData();
    setSaving(false);
  };

  return (
    <main className="min-h-screen p-4 sm:p-6 lg:p-8">
      <div className="mx-auto max-w-7xl space-y-6">
        <header className="flex flex-wrap items-end justify-between gap-3">
          <div><h1 className="text-2xl font-bold text-slate-900">Inventory &amp; batches</h1><p className="mt-1 text-sm text-slate-500">Track expiry-dated stock and auditable adjustments.</p></div>
          <Button variant="outline" onClick={() => void loadData()} disabled={loading}><RefreshCw className="mr-2 h-4 w-4" /> Refresh</Button>
        </header>

        {canAdjust && (
          <div className="grid gap-6 xl:grid-cols-2">
            <Card>
              <CardHeader><CardTitle>Add opening stock</CardTitle><CardDescription>Each batch is validated and written through the secure inventory RPC.</CardDescription></CardHeader>
              <CardContent>
                <form onSubmit={createBatch} className="grid gap-4 sm:grid-cols-2">
                  <div className="space-y-2 sm:col-span-2">
                    <Label htmlFor="inventoryProduct">Medicine *</Label>
                    <select id="inventoryProduct" className="h-10 w-full rounded-md border border-input bg-background px-3 text-sm" value={form.product_id} onChange={(event) => setBatchField('product_id', event.target.value)} required>
                      <option value="">Select a medicine</option>{products.map((product) => <option key={product.id} value={product.id}>{product.name}{product.strength ? ` · ${product.strength}` : ''}</option>)}
                    </select>
                    {products.length === 0 && <p className="text-xs text-amber-700">Create an active medicine first.</p>}
                  </div>
                  <div className="space-y-2"><Label htmlFor="batchNumber">Batch number *</Label><Input id="batchNumber" value={form.batch_number} onChange={(event) => setBatchField('batch_number', event.target.value)} required maxLength={120} /></div>
                  <div className="space-y-2"><Label htmlFor="batchExpiry">Expiry date *</Label><Input id="batchExpiry" type="date" min={dateInputMinimum()} value={form.expiry_date} onChange={(event) => setBatchField('expiry_date', event.target.value)} required /></div>
                  <div className="space-y-2"><Label htmlFor="batchManufacture">Manufacturing date</Label><Input id="batchManufacture" type="date" max={form.expiry_date || undefined} value={form.manufacturing_date} onChange={(event) => setBatchField('manufacturing_date', event.target.value)} /></div>
                  <div className="space-y-2"><Label htmlFor="batchQuantity">Quantity *</Label><Input id="batchQuantity" type="number" step="1" min="1" value={form.quantity} onChange={(event) => setBatchField('quantity', event.target.value)} required /></div>
                  <div className="space-y-2"><Label htmlFor="batchPurchasePrice">Purchase price *</Label><Input id="batchPurchasePrice" type="number" step="0.01" min="0" value={form.purchase_price} onChange={(event) => setBatchField('purchase_price', event.target.value)} required /></div>
                  <div className="space-y-2"><Label htmlFor="batchSellingPrice">Selling price *</Label><Input id="batchSellingPrice" type="number" step="0.01" min="0" value={form.selling_price} onChange={(event) => setBatchField('selling_price', event.target.value)} required /></div>
                  <div className="space-y-2"><Label htmlFor="batchMrp">MRP *</Label><Input id="batchMrp" type="number" step="0.01" min="0" value={form.mrp} onChange={(event) => setBatchField('mrp', event.target.value)} required /></div>
                  <div className="space-y-2"><Label htmlFor="batchSupplier">Supplier</Label><select id="batchSupplier" className="h-10 w-full rounded-md border border-input bg-background px-3 text-sm" value={form.supplier_id} onChange={(event) => setBatchField('supplier_id', event.target.value)}><option value="">No supplier</option>{suppliers.map((supplier) => <option key={supplier.id} value={supplier.id}>{supplier.name}</option>)}</select></div>
                  <div className="space-y-2 sm:col-span-2"><Label htmlFor="openingReason">Reason *</Label><Input id="openingReason" value={form.reason} onChange={(event) => setBatchField('reason', event.target.value)} minLength={5} maxLength={500} required /></div>
                  <div className="sm:col-span-2"><Button type="submit" className="bg-emerald-600 hover:bg-emerald-700" disabled={saving || products.length === 0}>{saving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Plus className="mr-2 h-4 w-4" />} Create batch</Button></div>
                </form>
              </CardContent>
            </Card>

            <Card>
              <CardHeader><CardTitle>Adjust stock</CardTitle><CardDescription>Positive or negative whole-unit adjustment with a recorded reason.</CardDescription></CardHeader>
              <CardContent>
                <form onSubmit={adjustStock} className="space-y-4">
                  <div className="space-y-2"><Label htmlFor="adjustBatch">Batch *</Label><select id="adjustBatch" className="h-10 w-full rounded-md border border-input bg-background px-3 text-sm" value={adjustBatchId} onChange={(event) => setAdjustBatchId(event.target.value)} required><option value="">Select a batch</option>{batches.map((batch) => <option key={batch.id} value={batch.id}>{batch.products.name} · {batch.batch_number} · {batch.available_qty} available · expires {batch.expiry_date}</option>)}</select></div>
                  <div className="space-y-2"><Label htmlFor="adjustQuantity">Quantity change (+/-) *</Label><Input id="adjustQuantity" type="number" step="1" value={adjustQuantity} onChange={(event) => setAdjustQuantity(event.target.value)} required /></div>
                  <div className="space-y-2"><Label htmlFor="adjustReason">Reason *</Label><Input id="adjustReason" value={adjustReason} onChange={(event) => setAdjustReason(event.target.value)} minLength={5} maxLength={500} required /></div>
                  <div className="space-y-2"><Label htmlFor="adjustReference">Reference (optional)</Label><Input id="adjustReference" value={adjustReference} onChange={(event) => setAdjustReference(event.target.value)} maxLength={120} /></div>
                  <Button type="submit" variant="outline" disabled={saving || batches.length === 0}>{saving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null} Record adjustment</Button>
                </form>
              </CardContent>
            </Card>
          </div>
        )}

        <Card>
          <CardHeader><CardTitle>Batch stock</CardTitle><CardDescription>Stock is tracked by batch; expired batches are not silently omitted.</CardDescription></CardHeader>
          <CardContent>
            {loading ? <div className="flex justify-center py-10"><Loader2 className="h-6 w-6 animate-spin text-emerald-600" /></div> : batches.length === 0 ? <p className="py-10 text-center text-sm text-slate-500">No inventory batches yet.</p> : (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[920px] text-left text-sm">
                  <thead className="border-b text-xs uppercase text-slate-500"><tr><th className="px-3 py-3">Medicine</th><th className="px-3 py-3">Batch</th><th className="px-3 py-3">Supplier</th><th className="px-3 py-3">Expiry</th><th className="px-3 py-3">Available</th><th className="px-3 py-3">Prices (buy / sell / MRP)</th><th className="px-3 py-3">Received</th></tr></thead>
                  <tbody className="divide-y">{batches.map((batch) => {
                    const expired = batch.expiry_date <= new Date().toISOString().slice(0, 10);
                    return <tr key={batch.id}>
                      <td className="px-3 py-4 font-medium">{batch.products.name}<p className="text-xs font-normal text-slate-500">{batch.products.sku || 'No SKU'}</p></td>
                      <td className="px-3 py-4">{batch.batch_number}</td><td className="px-3 py-4">{batch.suppliers?.name || '—'}</td>
                      <td className={`px-3 py-4 ${expired ? 'font-semibold text-red-700' : 'text-slate-600'}`}>{batch.expiry_date}{expired ? ' · Expired' : ''}</td>
                      <td className="px-3 py-4 font-medium">{batch.available_qty}</td>
                      <td className="px-3 py-4 text-slate-600">{Number(batch.purchase_price).toFixed(2)} / {Number(batch.selling_price).toFixed(2)} / {Number(batch.mrp).toFixed(2)}</td>
                      <td className="px-3 py-4">{batch.quantity_received}</td>
                    </tr>;
                  })}</tbody>
                </table>
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>Recent inventory movements</CardTitle><CardDescription>Latest 100 stock ledger entries for this pharmacy.</CardDescription></CardHeader>
          <CardContent>
            {loading ? <div className="flex justify-center py-10"><Loader2 className="h-6 w-6 animate-spin text-emerald-600" /></div> : movements.length === 0 ? <p className="py-10 text-center text-sm text-slate-500">No inventory movements recorded yet.</p> : (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[760px] text-left text-sm">
                  <thead className="border-b text-xs uppercase text-slate-500"><tr><th className="px-3 py-3">Date</th><th className="px-3 py-3">Medicine / batch</th><th className="px-3 py-3">Type</th><th className="px-3 py-3">Change</th><th className="px-3 py-3">Reason</th></tr></thead>
                  <tbody className="divide-y">{movements.map((movement) => <tr key={movement.id}>
                    <td className="px-3 py-4">{new Date(movement.created_at).toLocaleString()}</td>
                    <td className="px-3 py-4">{movement.products.name}<p className="text-xs text-slate-500">{movement.product_batches?.batch_number || 'No batch'}</p></td>
                    <td className="px-3 py-4 capitalize">{movement.movement_type.replaceAll('_', ' ')}</td>
                    <td className={`px-3 py-4 font-medium ${movement.quantity_delta < 0 ? 'text-red-700' : 'text-emerald-700'}`}>{movement.quantity_delta > 0 ? '+' : ''}{movement.quantity_delta}</td>
                    <td className="px-3 py-4 text-slate-600">{movement.note || movement.reference_type || '—'}</td>
                  </tr>)}</tbody>
                </table>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </main>
  );
}
