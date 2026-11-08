# simkuliah-presence-monitor Database Schema Specification

Single source of truth for database schema design, migrations, and indexing strategies.

- **Database Engine**: `postgres`

## 1. Migration Discipline
1. Never edit a committed `.sql` migration file; always author a new forward migration.
2. Every migration must provide both `UP` and `DOWN` (or reversible) logic.
3. Keep column naming conventions strictly snake_case (`created_at`, `updated_at`).

## 2. Core Entities & Tables

### `users`
| Column | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | UUID / INT | PRIMARY KEY | Unique identifier |
| `email` | VARCHAR(255) | UNIQUE, NOT NULL | Account email |
| `created_at` | TIMESTAMP WITH TIME ZONE | NOT NULL | Record creation timestamp |
| `updated_at` | TIMESTAMP WITH TIME ZONE | NOT NULL | Record last update timestamp |
