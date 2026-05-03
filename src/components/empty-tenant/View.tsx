import type { EmptyTenantData } from './types';

type EmptyTenantViewProps = {
  data?: EmptyTenantData;
};

export function EmptyTenantView({ data }: EmptyTenantViewProps) {
  const title = data?.title?.trim() || 'Your tenant is empty.';
  const description = data?.description?.trim() || 'Create your first page to start building your site.';

  return (
    <main className="min-h-screen flex items-center justify-center bg-background text-foreground px-6">
      <section className="w-full max-w-xl rounded-xl border border-border bg-card p-8 shadow-sm">
        <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
        <p className="mt-3 text-sm text-muted-foreground">{description}</p>
      </section>
    </main>
  );
}

