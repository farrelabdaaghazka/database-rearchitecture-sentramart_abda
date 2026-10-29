# SentraMart Database Re-Architecture & Reliability Engineering
**Take-Home Project UAS — Advanced Database Systems (Blok A, Oktober 2026)**  
**Universitas Cakrawala**

* **Mahasiswa:** Farrel Abda Aghazka
* **NIM:** 25110500003
* **Program Studi:** Data Science (Sains Data)
* **Environment Testing:** MacBook Pro 15-inch (2019) | Intel Core i7 2.6 GHz | RAM 16 GB DDR4 | PostgreSQL 16 & MongoDB 7.0 (Docker)

---

## 1. Deskripsi Proyek
Proyek ini merupakan hasil re-arsitektur dan *reliability engineering* atas basis data e-commerce SentraMart pasca insiden kritis Flash Sale Harbolnas 12.12.2025. Solusi dikembangkan pada skema baru (`v2`) yang terpisah penuh dari skema legacy, mencakup:
1. **Pembersihan & Deduplikasi Data:** Pemisahan PII, konversi EAV ke JSONB, dan penyaringan 515 transaksi pembayaran ganda (*double-charge*).
2. **Optimasi Kueri & Partitioning:** Penerapan *Range Partitioning* harian/tahunan, B-Tree Index, GIN Index `jsonb_path_ops`, dan *Materialized Views*.
3. **Pencegahan Anomali Konkurensi:** Stored Procedure berbasis *Pessimistic Row Locking* (`SELECT ... FOR UPDATE`) dan penyortiran array ID produk untuk mengeliminasi *overselling* dan *deadlock*.
4. **Polyglot Persistence (NoSQL):** Offloading data katalog EAV dan activity log ke MongoDB 7.0 untuk mempercepat kueri filter spesifikasi produk.
5. **Keamanan Enterprise (UU PDP Compliance):** Implementasi 4 *Least-Privilege Roles*, *Dynamic PII Masking View*, *Forced Row-Level Security* (RLS) seller, dan *Audit Logging Trigger*.

---

## 2. Struktur Berkas Repositori

```text
.
├── README.md                           # Panduan eksekusi end-to-end
├── sql/
│   ├── 01_audit.sql                    # Task 1: Audit data hygiene & kuantifikasi insiden legacy
│   ├── 02_schema_v2.sql                # Task 2: DDL Skema v2, Partitioning, & Constraints
│   ├── 03_migration.sql                # Task 2: Script ETL Cleansing, Normalisasi, & Deduplikasi
│   ├── 04_optimization.sql             # Task 3: DDL Indeks B-Tree/GIN & Materialized Views
│   ├── 05_transactions.sql             # Task 4: Stored Procedures & Pessimistic Locking
│   ├── 06_security.sql                 # Task 6: Least-Privilege Roles, RLS, & PII Masking
│   └── Test SLA.sql                    # Task 3: Script Benchmark EXPLAIN (ANALYZE, BUFFERS)
├── nosql/
│   ├── nosql_transform.ipynb           # Task 5: Python ETL Pipeline PostgreSQL to MongoDB
│   ├── mongo_queries.js                # Task 5: Kueri Bisnis BSON & Profiling explainStats
│   ├── activity_logs.json              # Task 5: Dataset Activity Logs
│   └── products.json                   # Task 5: Dataset Catalog Products
└── evidence/                           # Bukti Eksekusi & Screenshot
    ├── ERD.png
    ├── pii_masking.png
    └── rls_and_roles.png
```

---

## 3. Prasyarat System Environment

Sebelum mengeksekusi skrip, pastikan infrastruktur lokal telah aktif:
* **PostgreSQL 16** (Host: `localhost`, Port: `5432`, User: `postgres`)
* **MongoDB 7.0+** (Host: `localhost`, Port: `27017`)
* **Python 3.10+** beserta pustaka `psycopg2-binary`, `pymongo`, `bson`, dan `jupyter`
* Client SQL/NoSQL: `psql`, `mongosh`, atau **DBeaver**

---

## 4. End-to-End Execution Guide (Zero Error Setup)

Jalankan tahapan berikut secara sekuensial untuk membangun seluruh sistem dari kondisi database kosong hingga terverifikasi penuh:

### Langkah 1: Inisialisasi Database
Buka terminal dan siapkan database bersih `sentramart`:
```bash
# Hapus database jika ada, lalu buat database bersih
dropdb -U postgres --if-exists sentramart
createdb -U postgres sentramart
```
*(Catatan: Pastikan skema `legacy` dan dataset CSV bawaan telah dimuat ke database `sentramart` menggunakan `00_schema_v1.sql` dan `01_load_data.sql` sebelum melangkah ke Task 1)*.

### Langkah 2: Task 1 — Audit & Profiling Legacy
Mengeksekusi kueri audit untuk mengukur insiden overselling, double charge, dan data kotor di skema legacy:
```bash
psql -U postgres -d sentramart -f sql/01_audit.sql
```

### Langkah 3: Task 2 — Pembentukan Skema v2 & Migrasi Clean Data
Membentuk struktur skema `v2` (ENUM, Range Partitioning, Check Constraints, Foreign Keys), lalu mengeksekusi migrasi ETL:
```bash
# Pembentukan DDL Skema v2
psql -U postgres -d sentramart -f sql/02_schema_v2.sql

# Migrasi ETL, cleansing status, & pembersihan double-charge
psql -U postgres -d sentramart -f sql/03_migration.sql
```

### Langkah 4: Task 3 — Optimization Indexing & SLA Benchmark
Menerapkan B-Tree index, GIN index `jsonb_path_ops`, dan Materialized Views, dilanjutkan dengan pengujian *Execution Plan*:
```bash
# Terapkan DDL Indeks Optimasi & Materialized View
psql -U postgres -d sentramart -f sql/04_optimization.sql

# Jalankan Benchmark Workload (EXPLAIN ANALYZE)
psql -U postgres -d sentramart -f "sql/Test SLA.sql"
```

### Langkah 5: Task 4 — Stored Procedures & Kontrol Konkurensi
Memasang fungsi checkout idempoten berbasis *Pessimistic Row Locking* (`SELECT ... FOR UPDATE`) dan deterministic sorting:
```bash
psql -U postgres -d sentramart -f sql/05_transactions.sql
```

### Langkah 6: Task 5 — Pipeline NoSQL MongoDB
1. Eksekusi notebook ETL Python untuk mentransformasi katalog EAV ke BSON ter-embed dan mengisi koleksi `activity_logs`:
   ```bash
   jupyter nbconvert --execute --to notebook nosql/nosql_transform.ipynb
   ```
2. Jalankan kueri analitik BSON dan evaluasi statistik *Execution Plan*:
   ```bash
   mongosh "mongodb://localhost:27017/sentramart" nosql/mongo_queries.js
   ```

### Langkah 7: Task 6 — Keamanan Enterprise & Compliance UU PDP
Mengaktifkan 4 *Least-Privilege Roles*, *Dynamic PII Data Masking View*, *Row-Level Security* (RLS) seller, dan *Audit Logging Trigger*:
```bash
psql -U postgres -d sentramart -f sql/06_security.sql
```

---

## 5. Matriks Ringkasan Pencapaian Arsitektur

| Domain Task | Masalah Legacy (v1) | Solusi Arsitektur (v2) | Hasil Terukur |
| :--- | :--- | :--- | :--- |
| **Integritas Transaksi** | Stok minus & Double Charge 515 order | Stored Procedure `FOR UPDATE` + Partial Unique Index | **0% Overselling & 100% Idempotent** |
| **Pembersihan Data** | Raw text status & EAV 96k baris | Clean ETL + Pivot ke JSONB & BSON | **400.043 Orders Utuh (0 Variance)** |
| **Performansi Query** | Parallel Seq Scan pada jutaan baris | Range Partitioning + GIN Index `jsonb_path_ops` | **Latensi Kueri Transaksional < 10 ms** |
| **Polyglot Persistence** | Slow JOIN EAV (~45 ms) | Offloading ke MongoDB BSON Embedded Catalog | **Latensi Filter Produk ~1-3 ms** |
| **Keamanan & PDP** | All Connections via Superuser `postgres` | RBAC 4 Roles + Dynamic PII Masking View + RLS | **Pelanggaran PDP Terobati & Tenant Isolated** |

---

## 6. Verifikasi Akhir Pengujian
1. **PII Masking:** Kueri `SELECT * FROM v2.vw_customer_pii_masked LIMIT 3;` mengembalikan email/telepon tersamar (`ad************@outlook.com`).
2. **Isolasi Tenant:** Role `seller_portal` hanya dapat membaca produk sesuai variabel `app.current_seller_id`.
3. **Audit Log:** Perubahan harga/stok pada `v2.products` tercatat otomatis di `v2.audit_logs`.