# Supabase Database & Migration Patterns

## 1. Migration Discipline via Supabase CLI
- All schema changes must be authored as SQL migration files under `supabase/migrations/YYYYMMDDHHMMSS_name.sql`.
- Create new migrations using:
  ```bash
  supabase migration new <feature_name>
  ```
- Push local migrations to the linked Supabase cloud database:
  ```bash
  supabase db push
  ```
- Never mutate already committed migration files; always author a forward migration.

## 2. Row Level Security (RLS)
- Every table created must explicitly enable RLS:
  ```sql
  ALTER TABLE <table_name> ENABLE ROW LEVEL SECURITY;
  ```
- Provide explicit policies:
  - `service_role` full access for backend daemon operations.
  - `anon` read/write access scoped to client requirements.

## 3. Schema Documentation Synchronization
- Whenever a migration is authored, `docs/DATABASE_SCHEMA.md` must be updated in the same PR to remain the single source of truth.
