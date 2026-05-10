import { Icon } from '@/lib/IconResolver';
import { useFormState } from '@olonjs/core';
import type { FormDemoData } from './types';

type FormDemoViewProps = {
  data: FormDemoData;
};

const missingEnv =
  !import.meta.env.VITE_JSONPAGES_CLOUD_URL &&
  !import.meta.env.VITE_OLONJS_CLOUD_URL;

function SetupGuide({ recipientEmail }: { recipientEmail?: string }) {
  const steps = [
    {
      done: !!recipientEmail,
      label: 'recipientEmail nel JSON della sezione',
      code: '"recipientEmail": "tu@esempio.it"',
    },
    {
      done: !missingEnv,
      label: 'VITE_JSONPAGES_CLOUD_URL nel file .env',
      code: 'VITE_JSONPAGES_CLOUD_URL=https://cloud.olonjs.io',
    },
    {
      done: !!import.meta.env.VITE_JSONPAGES_API_KEY || !!import.meta.env.VITE_OLONJS_API_KEY,
      label: 'VITE_JSONPAGES_API_KEY nel file .env',
      code: 'VITE_JSONPAGES_API_KEY=sk-...',
    },
  ];

  const allDone = steps.every((s) => s.done);
  if (allDone) return null;

  return (
    <div className="rounded-lg border border-border bg-muted/40 p-4 space-y-3 text-sm">
      <p className="font-medium text-foreground">Quasi pronto — completa questi passaggi</p>
      <ol className="space-y-2">
        {steps.map((step, i) => (
          <li key={i} className="flex items-start gap-2">
            <span className={step.done ? 'text-green-500' : 'text-muted-foreground'}>
              {step.done ? '✓' : `${i + 1}.`}
            </span>
            <span className={step.done ? 'text-muted-foreground line-through' : 'text-foreground'}>
              {step.label}
              {!step.done && (
                <code className="block mt-0.5 text-xs bg-background rounded px-1.5 py-0.5 font-mono text-muted-foreground border border-border">
                  {step.code}
                </code>
              )}
            </span>
          </li>
        ))}
      </ol>
    </div>
  );
}

export function FormDemoView({ data }: FormDemoViewProps) {
  const formId = data.anchorId?.trim() || 'form-demo';
  const { status, message } = useFormState(formId);

  return (
    <main className="min-h-screen flex items-center justify-center bg-background text-foreground px-6">
      <section className="w-full max-w-xl rounded-xl border border-border bg-card p-8 shadow-sm space-y-6">
        {data.icon && (
          <div data-jp-field="icon" className="mb-2">
            <Icon name={data.icon} size={24} />
          </div>
        )}
        {data.title && (
          <div>
            <h1
              data-jp-field="title"
              className="text-2xl font-semibold tracking-tight"
            >
              {data.title}
            </h1>
            {data.description && (
              <p
                data-jp-field="description"
                className="mt-3 text-sm text-muted-foreground"
              >
                {data.description}
              </p>
            )}
          </div>
        )}

        <SetupGuide recipientEmail={data.recipientEmail} />

        <form
          id={formId}
          data-olon-recipient={data.recipientEmail ?? ''}
          className="space-y-4"
        >
          <div>
            <label className="block text-xs font-medium text-muted-foreground mb-1">
              Nome
            </label>
            <input
              name="name"
              type="text"
              required
              className="w-full rounded-md border border-border bg-background px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-primary"
            />
          </div>

          <div>
            <label className="block text-xs font-medium text-muted-foreground mb-1">
              Email
            </label>
            <input
              name="email"
              type="email"
              required
              className="w-full rounded-md border border-border bg-background px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-primary"
            />
          </div>

          <div>
            <label className="block text-xs font-medium text-muted-foreground mb-1">
              Messaggio
            </label>
            <textarea
              name="message"
              required
              rows={4}
              className="w-full rounded-md border border-border bg-background px-3 py-2 text-sm resize-none focus:outline-none focus:ring-1 focus:ring-primary"
            />
          </div>

          {status === 'error' && (
            <p className="text-xs text-destructive">{message}</p>
          )}
          {status === 'success' && (
            <p className="text-xs text-green-600">
              {data.successMessage || message}
            </p>
          )}

          <button
            type="submit"
            disabled={status === 'submitting'}
            className="w-full rounded-md bg-primary text-primary-foreground px-4 py-2 text-sm font-medium hover:opacity-90 disabled:opacity-60 disabled:cursor-not-allowed transition-opacity"
          >
            {status === 'submitting' ? 'Invio...' : (data.submitLabel || 'Invia')}
          </button>
        </form>
      </section>
    </main>
  );
}

