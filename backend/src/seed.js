import { initializeFirebase, getAuth, getDb, admin } from './config/firebase.js';
import env from './config/env.js';
import { resolveSeedPasswords, SEED_PASSWORD_ENV } from './config/seedCredentials.js';

/**
 * Seeds the Firestore database with initial data that mirrors the UI screens
 * of the Legal Services app, and creates a default admin user.
 *
 * Run with:  npm run seed
 */

const now = admin.firestore.FieldValue.serverTimestamp();

function ts() {
  return now;
}

async function seedUsers(db, auth, passwords) {
  const users = [
    {
      account: 'admin',
      uid: 'admin-uid',
      name: 'App Administrator',
      email: 'admin@legalapp.com',
      phone: '+1 555 0100',
      role: 'admin',
      avatar: 'images/c3.png',
      address: '100 Justice Ave, London',
      // Password: supplied via SEED_PASSWORD_ENV.admin (never hardcoded).
    },
    {
      account: 'client',
      uid: 'client-001',
      name: 'James Powell',
      email: 'james@example.com',
      phone: '+1 555 0111',
      role: 'client',
      avatar: 'images/c3.png',
      address: '22 Baker Street, London',
      // Password: supplied via SEED_PASSWORD_ENV.client (never hardcoded).
    },
    {
      account: 'lawyer',
      uid: 'lawyer-001',
      name: 'Maddy Lin',
      email: 'maddy@example.com',
      phone: '+1 555 0222',
      role: 'lawyer',
      avatar: 'images/c2.png',
      address: '5 High Court Road, London',
      // Password: supplied via SEED_PASSWORD_ENV.lawyer (never hardcoded).
    },
  ];

  for (const u of users) {
    // `account` selects the password; it is never written to Firestore.
    const { account, uid, ...profile } = u;
    const password = passwords[account];
    try {
      await auth.createUser({ uid, email: profile.email, password, displayName: profile.name });
    } catch (e) {
      if (e.code !== 'auth/uid-already-exists' && e.code !== 'auth/email-already-exists') {
        throw e;
      }
    }
    await db.collection('users').doc(uid).set({ ...profile, createdAt: ts(), updatedAt: ts() }, { merge: true });
  }
  console.log(`[Seed] Users: ${users.length}`);
}

async function seedLawyers(db) {
  const lawyers = [
    { name: 'Corporate Lawyer', specialty: 'Corporate Law', price: '$150/hr', priceValue: 150, image: 'images/layer1.png', rating: 4.8, location: 'Uk London', isPopular: true, isTop: true },
    { name: 'Family Lawyer', specialty: 'Family Law', price: '$120/hr', priceValue: 120, image: 'images/lawyer10.jpg', rating: 4.6, location: 'Uk London', isPopular: true, isTop: false },
    { name: 'Criminal Lawyer', specialty: 'Criminal Law', price: '$180/hr', priceValue: 180, image: 'images/lawyer3.png', rating: 4.9, location: 'Uk London', isPopular: true, isTop: true },
    { name: 'Intellectual Lawyer', specialty: 'Intellectual Property', price: '$200/hr', priceValue: 200, image: 'images/lawyer8.jpg', rating: 4.7, location: 'Uk London', isPopular: false, isTop: true },
    { name: 'Personal Injury Lawyer', specialty: 'Personal Injury', price: '$170/hr', priceValue: 170, image: 'images/lawyer7.jpg', rating: 4.5, location: 'Uk London', isPopular: false, isTop: false },
    { name: 'Tax Lawyer', specialty: 'Tax Law', price: '$160/hr', priceValue: 160, image: 'images/lawyer6.png', rating: 4.4, location: 'Uk London', isPopular: true, isTop: false },
    { name: 'Immigration Lawyer', specialty: 'Immigration Law', price: '$140/hr', priceValue: 140, image: 'images/lawyer4.jpg', rating: 4.3, location: 'Uk London', isPopular: false, isTop: false },
    { name: 'Employment Lawyer', specialty: 'Employment Law', price: '$130/hr', priceValue: 130, image: 'images/lawyer5.png', rating: 4.2, location: 'Uk London', isPopular: true, isTop: false },
    { name: 'Bankruptcy Lawyer', specialty: 'Bankruptcy Law', price: '$125/hr', priceValue: 125, image: 'images/lawyer9.jpg', rating: 4.1, location: 'Uk London', isPopular: false, isTop: false },
    { name: 'Real Estate Lawyer', specialty: 'Real Estate Law', price: '$135/hr', priceValue: 135, image: 'images/lawyer2.png', rating: 4.4, location: 'Uk London', isPopular: true, isTop: true },
  ];

  const batch = db.batch();
  for (const l of lawyers) {
    const ref = db.collection('lawyers').doc();
    batch.set(ref, { ...l, createdAt: ts(), updatedAt: ts() });
  }
  await batch.commit();
  console.log(`[Seed] Lawyers: ${lawyers.length}`);
}

async function seedPlans(db) {
  const plans = [
    {
      title: 'Basic Plan', price: '$ 0.00', priceValue: 0, color: '#D32F2F', isPopular: false,
      features: ['Once 5 Mins Allowed To Talk With Advocates Via Voice Call', 'Users Can Chat In Advocates Q & A Groups'],
    },
    {
      title: 'Silver Plan', price: '$ 799/- Inter Advocates', priceValue: 799, color: '#3498DB', isPopular: true,
      features: ['Once 5 Mins Allowed To Talk With Advocates Via Voice Call', 'Users Can Chat In Advocates Q & A Groups', 'User Can Hire An Family Intermediate Advocates', 'Book Advocates Appointment Schedule With In This App', 'Chat & Virtual Call Options Available'],
    },
    {
      title: 'Premium Plan', price: '$ 1499/- Senior Advocates', priceValue: 1499, color: '#FF5722', isPopular: false,
      features: ['Once 5 Mins Allowed To Talk With Advocates Via Voice Call', 'Users Can Chat In Advocates Q & A Groups', 'User Can Hire An Family Senior Advocates', 'Book Advocates Appointment Schedule With In This App', 'Chat & Virtual Call Options Available'],
    },
  ];
  const batch = db.batch();
  for (const p of plans) {
    const ref = db.collection('plans').doc();
    batch.set(ref, { ...p, createdAt: ts(), updatedAt: ts() });
  }
  await batch.commit();
  console.log(`[Seed] Plans: ${plans.length}`);
}

async function seedCases(db) {
  const cases = [
    { userId: 'client-001', title: 'Case #CL-2024-001: Smith v. Corp', description: 'Draft motion for summary judgment.', clientName: 'John Smith', caseType: 'Civil Litigation', priority: 'High', status: 'In Progress', dueDate: '2024-08-15' },
    { userId: 'client-001', title: 'Matter #RE-2024-015: Property Purchase', description: 'Review title report and prepare closing documents.', clientName: 'Jane Doe', caseType: 'Real Estate', priority: 'Medium', status: 'Open', dueDate: '2024-07-30' },
    { userId: 'client-001', title: 'Case #IP-2024-003: Patent Application', description: 'Respond to USPTO office action.', clientName: 'Innovate Inc.', caseType: 'Intellectual Property', priority: 'High', status: 'Pending', dueDate: '2024-09-01' },
    { userId: 'client-001', title: 'Matter #FL-2024-020: Davis Divorce', description: 'Client consultation regarding asset division.', clientName: 'Sarah Davis', caseType: 'Family Law', priority: 'Low', status: 'Open', dueDate: '2024-07-25' },
  ];
  const batch = db.batch();
  for (const c of cases) {
    const ref = db.collection('cases').doc();
    batch.set(ref, { ...c, createdAt: ts(), updatedAt: ts() });
  }
  await batch.commit();
  console.log(`[Seed] Cases: ${cases.length}`);
}

async function seedBookings(db) {
  const statuses = ['Active', 'Completed', 'Cancelled', 'Pending'];
  const names = ['Corporate Lawyer', 'Family Lawyer', 'Criminal Lawyer', 'Intellectual Lawyer'];
  const batch = db.batch();
  for (let i = 0; i < 8; i++) {
    const ref = db.collection('bookings').doc();
    batch.set(ref, {
      userId: 'client-001',
      lawyerId: 'lawyer-' + (i % 10),
      lawyerName: names[i % names.length],
      date: `2024-0${(i % 6) + 1}-1${i % 9}`,
      time: ['08:30 am', '09:00 am', '10:30 am', '11:00 am'][i % 4],
      hours: (i % 4) + 1,
      totalPrice: 150 * ((i % 4) + 1),
      status: statuses[i % statuses.length],
      createdAt: ts(),
      updatedAt: ts(),
    });
  }
  await batch.commit();
  console.log('[Seed] Bookings: 8');
}

async function seedTasks(db) {
  const tasks = [
    { userId: 'client-001', title: 'Draft motion for summary judgment.', description: 'Case #CL-2024-001', dueDate: '2024-08-15', priority: 'High', status: 'In Progress' },
    { userId: 'client-001', title: 'Review title report', description: 'Matter #RE-2024-015', dueDate: '2024-07-30', priority: 'Medium', status: 'To Do' },
    { userId: 'client-001', title: 'Respond to USPTO office action', description: 'Case #IP-2024-003', dueDate: '2024-09-01', priority: 'High', status: 'To Do' },
    { userId: 'client-001', title: 'Client consultation asset division', description: 'Matter #FL-2024-020', dueDate: '2024-07-25', priority: 'Low', status: 'Done' },
  ];
  const batch = db.batch();
  for (const t of tasks) {
    const ref = db.collection('tasks').doc();
    batch.set(ref, { ...t, createdAt: ts(), updatedAt: ts() });
  }
  await batch.commit();
  console.log(`[Seed] Tasks: ${tasks.length}`);
}

async function seedReviews(db) {
  const reviews = [
    { userId: 'client-001', userName: 'James Andre', lawyerId: 'lawyer-1', rating: 5, comment: 'Excellent legal advice and very professional service.' },
    { userId: 'client-001', userName: 'Powell Sumuled', lawyerId: 'lawyer-2', rating: 4, comment: 'Good communication and timely updates.' },
    { userId: 'client-001', userName: 'Hales Andreeed', lawyerId: 'lawyer-3', rating: 5, comment: 'Highly recommend for corporate matters.' },
    { userId: 'client-001', userName: 'Guptel Stin', lawyerId: 'lawyer-4', rating: 3, comment: 'Average experience, could improve response time.' },
  ];
  const batch = db.batch();
  for (const r of reviews) {
    const ref = db.collection('reviews').doc();
    batch.set(ref, { ...r, createdAt: ts(), updatedAt: ts() });
  }
  await batch.commit();
  console.log(`[Seed] Reviews: ${reviews.length}`);
}

async function seedNotifications(db) {
  const items = [
    { title: 'Booking Confirmed', content: 'Your appointment with Corporate Lawyer is confirmed.', type: 'booking', icon: 'check_circle' },
    { title: 'New Message', content: 'Maddy Lin sent you a message.', type: 'message', icon: 'message' },
    { title: 'Payment Received', content: 'Your payment for order #12345 has been received.', type: 'payment', icon: 'payment' },
    { title: 'Case Update', content: 'Case #CL-2024-001 status changed to In Progress.', type: 'case', icon: 'update' },
    { title: 'Reminder', content: 'You have an appointment tomorrow at 09:00 am.', type: 'reminder', icon: 'schedule' },
  ];
  const batch = db.batch();
  for (const n of items) {
    const ref = db.collection('notifications').doc();
    batch.set(ref, { userId: 'client-001', read: false, ...n, createdAt: ts(), updatedAt: ts() });
  }
  await batch.commit();
  console.log(`[Seed] Notifications: ${items.length}`);
}

async function seedChats(db) {
  const chatRef = db.collection('chats').doc('chat-client-001-lawyer-001');
  await chatRef.set(
    {
      participants: ['client-001', 'lawyer-001'],
      participantNames: { 'client-001': 'James Powell', 'lawyer-001': 'Maddy Lin' },
      lastMessage: 'Great. Thanks again!',
      updatedAt: ts(),
      createdAt: ts(),
    },
    { merge: true },
  );

  const messages = [
    { senderId: 'lawyer-001', senderName: 'Maddy Lin', text: "Hi James, I'm on the way. Please wait a moment.", createdAt: ts() },
    { senderId: 'client-001', senderName: 'James Powell', text: "Thank You! I'll be waiting.", createdAt: ts() },
    { senderId: 'lawyer-001', senderName: 'Maddy Lin', text: "Okay, I'm here. Where should we meet?", createdAt: ts() },
    { senderId: 'client-001', senderName: 'James Powell', text: 'Sure. I will be there in a minute.', createdAt: ts() },
    { senderId: 'lawyer-001', senderName: 'Maddy Lin', text: 'Great. Thanks again!', createdAt: ts() },
  ];
  const batch = db.batch();
  for (const m of messages) {
    const ref = chatRef.collection('messages').doc();
    batch.set(ref, m);
  }
  await batch.commit();
  console.log(`[Seed] Chats: 1 (${messages.length} messages)`);
}

async function seedWallet(db) {
  await db.collection('wallets').doc('client-001').set(
    { userId: 'client-001', balance: 12000, currency: 'USD', updatedAt: ts(), createdAt: ts() },
    { merge: true },
  );
  const txs = [
    { type: 'credit', amount: 5000, description: 'Money Added To Wallet' },
    { type: 'debit', amount: 1500, description: 'Booking: Corporate Lawyer' },
    { type: 'credit', amount: 8500, description: 'Top up via card' },
  ];
  const batch = db.batch();
  for (const t of txs) {
    const ref = db.collection('wallet_transactions').doc();
    batch.set(ref, { userId: 'client-001', balance: 12000, ...t, createdAt: ts() });
  }
  await batch.commit();
  console.log(`[Seed] Wallet transactions: ${txs.length}`);
}

async function seedAvailability(db) {
  const dates = ['2024-07-01', '2024-07-02', '2024-07-03', '2024-07-04', '2024-07-05'];
  const slots = ['08:30 am', '09:00 am', '10:30 am', '11:00 am', '01:00 pm', '02:30 pm'];
  const batch = db.batch();
  for (const d of dates) {
    const ref = db.collection('availability').doc();
    batch.set(ref, { lawyerId: 'lawyer-001', lawyerName: 'Maddy Lin', date: d, slots, createdAt: ts(), updatedAt: ts() });
  }
  await batch.commit();
  console.log(`[Seed] Availability: ${dates.length} days`);
}

async function seedFavorites(db) {
  const batch = db.batch();
  for (const id of ['lawyer-1', 'lawyer-3', 'lawyer-6']) {
    const ref = db.collection('favorites').doc();
    batch.set(ref, { userId: 'client-001', lawyerId: id, createdAt: ts() });
  }
  await batch.commit();
  console.log('[Seed] Favorites: 3');
}

async function seedEarnings(db) {
  await db.collection('earnings').doc('client-001').set(
    {
      userId: 'client-001',
      balance: 1250.75,
      totalEarnings: 1250.75,
      breakdown: { baseFare: 820.0, distance: 220.5, tips: 85.75, bonuses: 125.0, referral: 100.0, surge: 50.0 },
      updatedAt: ts(),
      createdAt: ts(),
    },
    { merge: true },
  );
  console.log('[Seed] Earnings: 1');
}

export async function runSeed() {
  // Resolve credentials FIRST. A missing or unusable password must abort the
  // run before a single document or Auth account is touched, so a broken
  // configuration can never leave a half-seeded project behind.
  const passwords = resolveSeedPasswords();
  console.log(
    `[Seed] Credentials read from ${Object.values(SEED_PASSWORD_ENV).join(', ')}`,
  );

  const { firestore: db } = initializeFirebase();
  const auth = getAuth();

  console.log('\n===== Seeding Legal Services database =====\n');
  await seedUsers(db, auth, passwords);
  await seedLawyers(db);
  await seedPlans(db);
  await seedCases(db);
  await seedBookings(db);
  await seedTasks(db);
  await seedReviews(db);
  await seedNotifications(db);
  await seedChats(db);
  await seedWallet(db);
  await seedAvailability(db);
  await seedFavorites(db);
  await seedEarnings(db);
  console.log('\n===== Seed complete =====\n');
}

// Allow running directly:  node src/seed.js
if (import.meta.url === `file://${process.argv[1]}`) {
  runSeed()
    .then(() => process.exit(0))
    .catch((e) => {
      console.error('[Seed] Failed:', e);
      process.exit(1);
    });
}
