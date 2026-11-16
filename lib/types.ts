export type PharmacyStatus = 'pending' | 'approved' | 'rejected' | 'suspended' | 'deactivated';

export interface Pharmacy {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  address_line1: string | null;
  address_line2: string | null;
  city: string | null;
  state: string | null;
  postal_code: string | null;
  country: string;
  drug_license_number: string | null;
  tax_id: string | null;
  rejection_reason: string | null;
  logo_path: string | null;
  submitted_at: string;
  owner_id: string | null;
  status: PharmacyStatus;
  approved_at: string | null;
  approved_by: string | null;
  suspended_at: string | null;
  deactivated_at: string | null;
  settings: {
    expiry_alert_days?: number[];
    tax_rate?: number;
    currency?: string;
    invoice_prefix?: string;
  };
  created_at: string;
  updated_at: string;
}

export interface AppUser {
  id: string;
  email: string;
  full_name: string | null;
  phone: string | null;
  is_super_admin: boolean;
  created_at: string;
  updated_at: string;
}

export interface Role {
  id: string;
  pharmacy_id: string | null;
  name: string;
  description: string | null;
  is_system: boolean;
  created_at: string;
  updated_at: string;
}

export interface Permission {
  id: string;
  key: string;
  module: string;
  action: string;
  description: string | null;
}

export interface PharmacyMember {
  id: string;
  pharmacy_id: string;
  user_id: string;
  role_id: string;
  invited_by: string | null;
  invited_at: string;
  accepted_at: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
  role?: Role;
  app_user?: AppUser;
}

export interface SubscriptionPlan {
  id: string;
  name: string;
  description: string | null;
  price_monthly: number;
  price_yearly: number;
  currency: string;
  max_users: number | null;
  max_products: number | null;
  features: Record<string, boolean>;
  is_active: boolean;
  trial_days: number;
  created_at: string;
  updated_at: string;
}

export interface Subscription {
  id: string;
  pharmacy_id: string;
  plan_id: string;
  status: 'trialing' | 'active' | 'past_due' | 'canceled' | 'expired';
  billing_cycle: 'monthly' | 'yearly';
  current_period_start: string;
  current_period_end: string | null;
  trial_ends_at: string | null;
  canceled_at: string | null;
  created_at: string;
  updated_at: string;
  plan?: SubscriptionPlan;
}

export interface Category {
  id: string;
  pharmacy_id: string;
  name: string;
  description: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface Generic {
  id: string;
  pharmacy_id: string;
  name: string;
  description: string | null;
  created_at: string;
  updated_at: string;
}

export interface Manufacturer {
  id: string;
  pharmacy_id: string;
  name: string;
  contact_person: string | null;
  phone: string | null;
  email: string | null;
  address: string | null;
  created_at: string;
  updated_at: string;
}

export interface Brand {
  id: string;
  pharmacy_id: string;
  name: string;
  manufacturer_id: string | null;
  created_at: string;
  updated_at: string;
}

export interface DosageForm {
  id: string;
  pharmacy_id: string;
  name: string;
  created_at: string;
  updated_at: string;
}

export interface Unit {
  id: string;
  pharmacy_id: string;
  name: string;
  abbreviation: string | null;
  created_at: string;
  updated_at: string;
}

export interface Supplier {
  id: string;
  pharmacy_id: string;
  name: string;
  contact_person: string | null;
  phone: string | null;
  email: string | null;
  address: string | null;
  tax_id: string | null;
  opening_balance: number;
  current_balance: number;
  notes: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface Customer {
  id: string;
  pharmacy_id: string;
  name: string;
  phone: string | null;
  email: string | null;
  address: string | null;
  date_of_birth: string | null;
  gender: 'male' | 'female' | 'other' | null;
  opening_balance: number;
  current_balance: number;
  notes: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface Product {
  id: string;
  pharmacy_id: string;
  name: string;
  generic_name: string | null;
  generic_id: string | null;
  brand_id: string | null;
  manufacturer_id: string | null;
  category_id: string | null;
  dosage_form_id: string | null;
  strength: string | null;
  unit_id: string | null;
  pack_size: number | null;
  sku: string | null;
  barcode: string | null;
  purchase_price: number;
  selling_price: number;
  wholesale_price: number;
  reorder_level: number;
  description: string | null;
  image_url: string | null;
  requires_prescription: boolean;
  status: 'active' | 'archived';
  total_stock: number;
  created_at: string;
  updated_at: string;
}

export interface ProductBatch {
  id: string;
  product_id: string;
  pharmacy_id: string;
  batch_number: string;
  manufacturing_date: string | null;
  expiry_date: string;
  purchase_price: number;
  selling_price: number;
  mrp: number;
  quantity_received: number;
  available_qty: number;
  supplier_id: string | null;
  purchase_id: string | null;
  is_expired_override: boolean;
  created_at: string;
  updated_at: string;
}

export interface InventoryMovement {
  id: string;
  product_id: string;
  batch_id: string | null;
  pharmacy_id: string;
  movement_type: 'purchase' | 'sale' | 'sale_return' | 'adjustment' | 'transfer_in' | 'transfer_out';
  quantity_delta: number;
  reference_type: string | null;
  reference_id: string | null;
  created_by: string | null;
  note: string | null;
  created_at: string;
}

export interface Sale {
  id: string;
  pharmacy_id: string;
  invoice_number: string;
  customer_id: string | null;
  sold_by: string | null;
  sale_date: string;
  subtotal: number;
  discount_amount: number;
  tax_amount: number;
  total: number;
  paid_amount: number;
  due_amount: number;
  change_amount: number;
  status: 'held' | 'completed' | 'canceled' | 'refunded';
  prescription_id: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
  customer?: Customer;
  sale_items?: SaleItem[];
  sale_payments?: SalePayment[];
}

export interface SaleItem {
  id: string;
  sale_id: string;
  pharmacy_id: string;
  product_id: string;
  batch_id: string | null;
  quantity: number;
  unit_price: number;
  discount_amount: number;
  tax_amount: number;
  line_total: number;
  created_at: string;
  product?: Product;
}

export interface SalePayment {
  id: string;
  sale_id: string;
  pharmacy_id: string;
  amount: number;
  method: 'cash' | 'card' | 'mobile' | 'bank_transfer' | 'credit';
  reference: string | null;
  paid_at: string;
  created_at: string;
}

export interface SaleReturn {
  id: string;
  pharmacy_id: string;
  sale_id: string;
  return_number: string;
  customer_id: string | null;
  total: number;
  reason: string | null;
  returned_by: string | null;
  approved_by: string | null;
  status: 'pending' | 'approved' | 'rejected';
  created_at: string;
  updated_at: string;
}

export interface Purchase {
  id: string;
  pharmacy_id: string;
  purchase_number: string;
  supplier_id: string | null;
  purchased_by: string | null;
  approved_by: string | null;
  purchase_date: string;
  subtotal: number;
  discount_amount: number;
  tax_amount: number;
  total: number;
  paid_amount: number;
  due_amount: number;
  status: 'draft' | 'ordered' | 'received' | 'canceled';
  notes: string | null;
  created_at: string;
  updated_at: string;
  supplier?: Supplier;
  purchase_items?: PurchaseItem[];
}

export interface PurchaseItem {
  id: string;
  purchase_id: string;
  pharmacy_id: string;
  product_id: string;
  batch_id: string | null;
  batch_number: string | null;
  manufacturing_date: string | null;
  expiry_date: string | null;
  quantity: number;
  unit_cost: number;
  discount_amount: number;
  tax_amount: number;
  line_total: number;
  created_at: string;
  product?: Product;
}

export interface Expense {
  id: string;
  pharmacy_id: string;
  category: string;
  description: string | null;
  amount: number;
  expense_date: string;
  paid_by: string | null;
  reference: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

export interface Prescription {
  id: string;
  pharmacy_id: string;
  customer_id: string | null;
  prescriber_name: string | null;
  prescriber_license: string | null;
  prescription_date: string;
  image_url: string | null;
  notes: string | null;
  status: 'active' | 'dispensed' | 'expired' | 'canceled';
  created_by: string | null;
  created_at: string;
  updated_at: string;
}
