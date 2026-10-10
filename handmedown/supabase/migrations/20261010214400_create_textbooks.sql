create table public.textbooks (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(trim(title)) > 0),
  author text not null check (char_length(trim(author)) > 0),
  isbn text,
  course text,
  condition text not null check (condition in ('New', 'Good', 'Average', 'Damaged')),
  created_at timestamptz not null default now()
);

create index textbooks_created_at_idx on public.textbooks (created_at desc);

alter table public.textbooks enable row level security;

grant select, insert on public.textbooks to anon, authenticated;

create policy "Anyone can view textbooks"
  on public.textbooks for select
  to anon, authenticated
  using (true);

create policy "Anyone can list a textbook"
  on public.textbooks for insert
  to anon, authenticated
  with check (true);
