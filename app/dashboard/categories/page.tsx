'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';
import { Loader2, Pencil, Plus, X } from 'lucide-react';
import { toast } from 'sonner';
import { useAuth, usePermission } from '@/lib/auth-provider';
import { supabase } from '@/lib/supabase/client';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

interface Category {
  id: string;
  name: string;
  description: string | null;
  is_active: boolean;
  created_at: string;
}

export default function CategoriesPage() {
  const { pharmacy } = useAuth();
  const canCreate = usePermission('categories.create');
  const canEdit = usePermission('categories.edit');
  const [categories, setCategories] = useState<Category[]>([]);
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [editingId, setEditingId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const loadCategories = useCallback(async () => {
    if (!pharmacy) return;
    setLoading(true);
    const { data, error } = await supabase
      .from('categories')
      .select('id,name,description,is_active,created_at')
      .eq('pharmacy_id', pharmacy.id)
      .order('name');
    if (error) {
      toast.error(`Could not load categories: ${error.message}`);
      setLoading(false);
      return;
    }
    setCategories(data ?? []);
    setLoading(false);
  }, [pharmacy]);

  useEffect(() => { void loadCategories(); }, [loadCategories]);

  const reset = () => {
    setEditingId(null);
    setName('');
    setDescription('');
  };

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!pharmacy || (editingId ? !canEdit : !canCreate)) {
      toast.error('You do not have permission to change categories.');
      return;
    }
    const cleanedName = name.trim();
    if (cleanedName.length < 2) {
      toast.error('Category name must contain at least 2 characters.');
      return;
    }
    setSaving(true);
    const payload = { name: cleanedName, description: description.trim() || null };
    const result = editingId
      ? await supabase.from('categories').update(payload).eq('id', editingId).eq('pharmacy_id', pharmacy.id).select('id').maybeSingle()
      : await supabase.from('categories').insert({ ...payload, pharmacy_id: pharmacy.id }).select('id').maybeSingle();
    if (result.error) {
      toast.error(`Could not save category: ${result.error.message}`);
      setSaving(false);
      return;
    }
    if (!result.data) {
      toast.error('No category was changed. Check your access and try again.');
      setSaving(false);
      return;
    }
    toast.success(editingId ? 'Category updated.' : 'Category created.');
    reset();
    await loadCategories();
    setSaving(false);
  };

  const toggleActive = async (category: Category) => {
    if (!pharmacy || !canEdit) {
      toast.error('You do not have permission to change category status.');
      return;
    }
    const { error } = await supabase.from('categories').update({ is_active: !category.is_active }).eq('id', category.id).eq('pharmacy_id', pharmacy.id);
    if (error) {
      toast.error(`Could not update category status: ${error.message}`);
      return;
    }
    toast.success(`${category.name} ${category.is_active ? 'deactivated' : 'activated'}.`);
    await loadCategories();
  };

  return (
    <main className="min-h-screen p-4 sm:p-6 lg:p-8">
      <div className="mx-auto max-w-5xl space-y-6">
        <header className="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h1 className="text-2xl font-bold text-slate-900">Categories</h1>
            <p className="mt-1 text-sm text-slate-500">Organize the medicines in your pharmacy catalog.</p>
          </div>
          <p className="text-sm text-slate-500">{categories.filter((category) => category.is_active).length} active</p>
        </header>

        {(editingId ? canEdit : canCreate) && (
          <Card>
            <CardHeader>
              <div className="flex items-center justify-between gap-3">
                <div><CardTitle>{editingId ? 'Edit category' : 'Add category'}</CardTitle><CardDescription>Names must be unique within your pharmacy.</CardDescription></div>
                {editingId && <Button variant="ghost" size="sm" onClick={reset}><X className="mr-1 h-4 w-4" /> Cancel</Button>}
              </div>
            </CardHeader>
            <CardContent>
              <form onSubmit={submit} className="grid gap-4 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="categoryName">Category name *</Label>
                  <Input id="categoryName" value={name} onChange={(event) => setName(event.target.value)} minLength={2} maxLength={120} required />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="categoryDescription">Description</Label>
                  <Input id="categoryDescription" value={description} onChange={(event) => setDescription(event.target.value)} maxLength={500} />
                </div>
                <div className="sm:col-span-2">
                  <Button type="submit" className="bg-emerald-600 hover:bg-emerald-700" disabled={saving}>
                    {saving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Plus className="mr-2 h-4 w-4" />}
                    {editingId ? 'Save category' : 'Add category'}
                  </Button>
                </div>
              </form>
            </CardContent>
          </Card>
        )}

        <Card>
          <CardHeader><CardTitle>All categories</CardTitle><CardDescription>Deactivated categories remain available on existing product records.</CardDescription></CardHeader>
          <CardContent>
            {loading ? (
              <div className="flex justify-center py-10"><Loader2 className="h-6 w-6 animate-spin text-emerald-600" /></div>
            ) : categories.length === 0 ? (
              <p className="py-10 text-center text-sm text-slate-500">No categories yet.</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[560px] text-left text-sm">
                  <thead className="border-b text-xs uppercase text-slate-500"><tr><th className="px-3 py-3">Name</th><th className="px-3 py-3">Description</th><th className="px-3 py-3">Status</th><th className="px-3 py-3">Actions</th></tr></thead>
                  <tbody className="divide-y">
                    {categories.map((category) => (
                      <tr key={category.id}>
                        <td className="px-3 py-4 font-medium text-slate-900">{category.name}</td>
                        <td className="px-3 py-4 text-slate-600">{category.description || '—'}</td>
                        <td className="px-3 py-4">{category.is_active ? 'Active' : 'Inactive'}</td>
                        <td className="px-3 py-4">
                          <div className="flex gap-2">
                            {canEdit && <Button size="sm" variant="outline" onClick={() => { setEditingId(category.id); setName(category.name); setDescription(category.description ?? ''); }}><Pencil className="mr-1 h-3.5 w-3.5" /> Edit</Button>}
                            {canEdit && <Button size="sm" variant="outline" onClick={() => void toggleActive(category)}>{category.is_active ? 'Deactivate' : 'Activate'}</Button>}
                          </div>
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
