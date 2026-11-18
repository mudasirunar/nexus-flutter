/**
 * Standalone idempotent Firestore seed script for NEXUS.
 * Uses `scripts/serviceAccountKey.json` (gitignored).
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const keyPath = resolve('scripts/serviceAccountKey.json');
const serviceAccount = JSON.parse(readFileSync(keyPath, 'utf8'));

initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

const now = Date.now();
const dayMs = 24 * 60 * 60 * 1000;

const branches = [
  {
    id: 'branch-downtown',
    name: 'Downtown Flagship',
    location: '120 Market St',
    phone: '+1 555-0101',
    isActive: true,
    updatedAt: now,
    isDeleted: false,
    deletedAt: null,
  },
  {
    id: 'branch-airport',
    name: 'Airport Express',
    location: 'Terminal 2, Concourse B',
    phone: '+1 555-0102',
    isActive: true,
    updatedAt: now,
    isDeleted: false,
    deletedAt: null,
  },
  {
    id: 'branch-westside',
    name: 'Westside Hub',
    location: '480 Oak Avenue',
    phone: '+1 555-0103',
    isActive: true,
    updatedAt: now,
    isDeleted: false,
    deletedAt: null,
  },
];

const products = [
  {
    id: 'prod-macbook-air',
    name: 'UltraBook Air 14"',
    sku: 'UBA-14-256',
    barcode: '890100000001',
    category: 'Laptops',
    costPrice: 820,
    sellingPrice: 1099,
    lowStockThreshold: 4,
    imageUrl: null,
    updatedAt: now,
    isDeleted: false,
    deletedAt: null,
  },
  {
    id: 'prod-usbc-hub',
    name: 'USB-C 7-in-1 Hub',
    sku: 'HUB-7IN1',
    barcode: '890100000002',
    category: 'Accessories',
    costPrice: 18,
    sellingPrice: 39,
    lowStockThreshold: 8,
    imageUrl: null,
    updatedAt: now,
    isDeleted: false,
    deletedAt: null,
  },
  {
    id: 'prod-mech-kb',
    name: 'Mechanical Keyboard TKL',
    sku: 'KB-TKL-PRO',
    barcode: '890100000003',
    category: 'Peripherals',
    costPrice: 48,
    sellingPrice: 89,
    lowStockThreshold: 5,
    imageUrl: null,
    updatedAt: now,
    isDeleted: false,
    deletedAt: null,
  },
  {
    id: 'prod-wireless-mouse',
    name: 'Ergonomic Wireless Mouse',
    sku: 'MS-ERGO-2',
    barcode: '890100000004',
    category: 'Peripherals',
    costPrice: 22,
    sellingPrice: 49,
    lowStockThreshold: 6,
    imageUrl: null,
    updatedAt: now,
    isDeleted: false,
    deletedAt: null,
  },
  {
    id: 'prod-4k-monitor',
    name: '27" 4K IPS Monitor',
    sku: 'MON-27-4K',
    barcode: '890100000005',
    category: 'Displays',
    costPrice: 240,
    sellingPrice: 369,
    lowStockThreshold: 3,
    imageUrl: null,
    updatedAt: now,
    isDeleted: false,
    deletedAt: null,
  },
  {
    id: 'prod-anc-headphones',
    name: 'Studio ANC Headphones',
    sku: 'AUD-ANC-1',
    barcode: '890100000006',
    category: 'Audio',
    costPrice: 95,
    sellingPrice: 179,
    lowStockThreshold: 5,
    imageUrl: null,
    updatedAt: now,
    isDeleted: false,
    deletedAt: null,
  },
];

const stockMatrix = {
  'branch-downtown': {
    'prod-macbook-air': 12,
    'prod-usbc-hub': 25,
    'prod-mech-kb': 14,
    'prod-wireless-mouse': 3,
    'prod-4k-monitor': 8,
    'prod-anc-headphones': 11,
  },
  'branch-airport': {
    'prod-macbook-air': 5,
    'prod-usbc-hub': 18,
    'prod-mech-kb': 7,
    'prod-wireless-mouse': 15,
    'prod-4k-monitor': 2,
    'prod-anc-headphones': 9,
  },
  'branch-westside': {
    'prod-macbook-air': 9,
    'prod-usbc-hub': 6,
    'prod-mech-kb': 10,
    'prod-wireless-mouse': 12,
    'prod-4k-monitor': 6,
    'prod-anc-headphones': 7,
  },
};

const transactions = [
  {
    id: 'seed-tx-1',
    branchId: 'branch-downtown',
    type: 'sale',
    totalAmount: 1177,
    profitAmount: 321,
    notes: 'Corporate workstation order',
    createdBy: 'seed-script',
    createdAt: now - 3 * dayMs,
    updatedAt: now - 3 * dayMs,
    isDeleted: false,
    deletedAt: null,
    items: [
      {
        id: 'seed-item-1a',
        transactionId: 'seed-tx-1',
        productId: 'prod-macbook-air',
        productName: 'UltraBook Air 14"',
        quantity: 1,
        unitPrice: 1099,
        unitCost: 820,
      },
      {
        id: 'seed-item-1b',
        transactionId: 'seed-tx-1',
        productId: 'prod-usbc-hub',
        productName: 'USB-C 7-in-1 Hub',
        quantity: 2,
        unitPrice: 39,
        unitCost: 18,
      },
    ],
  },
  {
    id: 'seed-tx-2',
    branchId: 'branch-airport',
    type: 'sale',
    totalAmount: 407,
    profitAmount: 147,
    notes: 'Traveler bundle',
    createdBy: 'seed-script',
    createdAt: now - 2 * dayMs,
    updatedAt: now - 2 * dayMs,
    isDeleted: false,
    deletedAt: null,
    items: [
      {
        id: 'seed-item-2a',
        transactionId: 'seed-tx-2',
        productId: 'prod-anc-headphones',
        productName: 'Studio ANC Headphones',
        quantity: 2,
        unitPrice: 179,
        unitCost: 95,
      },
      {
        id: 'seed-item-2b',
        transactionId: 'seed-tx-2',
        productId: 'prod-wireless-mouse',
        productName: 'Ergonomic Wireless Mouse',
        quantity: 1,
        unitPrice: 49,
        unitCost: 22,
      },
    ],
  },
  {
    id: 'seed-tx-3',
    branchId: 'branch-westside',
    type: 'purchase',
    totalAmount: 480,
    profitAmount: 0,
    notes: 'Monitor restock PO-104',
    createdBy: 'seed-script',
    createdAt: now - dayMs,
    updatedAt: now - dayMs,
    isDeleted: false,
    deletedAt: null,
    items: [
      {
        id: 'seed-item-3a',
        transactionId: 'seed-tx-3',
        productId: 'prod-4k-monitor',
        productName: '27" 4K IPS Monitor',
        quantity: 2,
        unitPrice: 240,
        unitCost: 240,
      },
    ],
  },
  {
    id: 'seed-tx-4',
    branchId: 'branch-downtown',
    type: 'sale',
    totalAmount: 547,
    profitAmount: 211,
    notes: 'Walk-in retail sale',
    createdBy: 'seed-script',
    createdAt: now - 3600000,
    updatedAt: now - 3600000,
    isDeleted: false,
    deletedAt: null,
    items: [
      {
        id: 'seed-item-4a',
        transactionId: 'seed-tx-4',
        productId: 'prod-4k-monitor',
        productName: '27" 4K IPS Monitor',
        quantity: 1,
        unitPrice: 369,
        unitCost: 240,
      },
      {
        id: 'seed-item-4b',
        transactionId: 'seed-tx-4',
        productId: 'prod-mech-kb',
        productName: 'Mechanical Keyboard TKL',
        quantity: 2,
        unitPrice: 89,
        unitCost: 48,
      },
    ],
  },
];

async function seed() {
  const batch = db.batch();

  for (const b of branches) {
    batch.set(db.collection('branches').doc(b.id), b, { merge: true });
  }
  for (const p of products) {
    batch.set(db.collection('products').doc(p.id), p, { merge: true });
  }
  for (const [branchId, items] of Object.entries(stockMatrix)) {
    for (const [productId, quantity] of Object.entries(items)) {
      const id = `${branchId}_${productId}`;
      batch.set(
        db.collection('branch_stock').doc(id),
        {
          id,
          branchId,
          productId,
          quantity,
          updatedAt: now,
          isDeleted: false,
          deletedAt: null,
        },
        { merge: true },
      );
    }
  }
  for (const tx of transactions) {
    batch.set(db.collection('transactions').doc(tx.id), tx, { merge: true });
  }

  await batch.commit();
  console.log('Seeded 3 branches, 6 products, 18 branch_stock records, and 4 transactions.');
}

seed().catch((err) => {
  console.error(err);
  process.exit(1);
});
