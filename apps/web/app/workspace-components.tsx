import Link from "next/link";
import type { ReactNode } from "react";

type PageWorkspaceProps = {
  children: ReactNode;
  className?: string;
};

type PageHeaderProps = {
  eyebrow?: string;
  title: string;
  description: string;
  actions?: ReactNode;
};

export type DomainNavigationItem = {
  key: string;
  href: string;
  label: string;
};

type DomainNavigationProps = {
  items: DomainNavigationItem[];
  active: string;
  label: string;
  ariaLabel: string;
};

type DomainShellProps = PageHeaderProps & {
  children: ReactNode;
  items: DomainNavigationItem[];
  active: string;
  navigationLabel: string;
  navigationAriaLabel: string;
  className?: string;
};

export type WorkflowGuideStep = {
  title: string;
  description: string;
  href?: string;
};

type WorkflowGuideProps = {
  steps: WorkflowGuideStep[];
  ariaLabel: string;
};

export function PageWorkspace({ children, className = "" }: PageWorkspaceProps) {
  return <section className={`workspace page-workspace ${className}`.trim()}>{children}</section>;
}

export function PageHeader({ eyebrow, title, description, actions }: PageHeaderProps) {
  return (
    <header className="page-header">
      <div className="page-header-copy">
        {eyebrow ? <span className="eyebrow">{eyebrow}</span> : null}
        <h1>{title}</h1>
        <p className="muted">{description}</p>
      </div>
      {actions ? <div className="page-actions">{actions}</div> : null}
    </header>
  );
}

export function WorkflowGuide({ steps, ariaLabel }: WorkflowGuideProps) {
  return (
    <ol className="workflow-guide" aria-label={ariaLabel}>
      {steps.map((step, index) => {
        const content = (
          <>
            <span className="workflow-guide-number" aria-hidden="true">{index + 1}</span>
            <span className="workflow-guide-copy">
              <strong>{step.title}</strong>
              <small>{step.description}</small>
            </span>
          </>
        );

        return (
          <li key={`${index}-${step.title}`}>
            {step.href ? <Link href={step.href}>{content}</Link> : <div>{content}</div>}
          </li>
        );
      })}
    </ol>
  );
}

export function DomainNavigation({ items, active, label, ariaLabel }: DomainNavigationProps) {
  const activeLabel = items.find((item) => item.key === active)?.label ?? label;

  return (
    <>
      <nav className="domain-navigation domain-navigation-desktop" aria-label={ariaLabel}>
        {items.map((item) => (
          <Link key={item.key} href={item.href} aria-current={active === item.key ? "page" : undefined}>
            {item.label}
          </Link>
        ))}
      </nav>

      <details className="domain-navigation-mobile">
        <summary>
          <span>{label}</span>
          <strong>{activeLabel}</strong>
        </summary>
        <nav className="domain-navigation" aria-label={ariaLabel}>
          {items.map((item) => (
            <Link key={item.key} href={item.href} aria-current={active === item.key ? "page" : undefined}>
              {item.label}
            </Link>
          ))}
        </nav>
      </details>
    </>
  );
}

export function DomainShell({
  children,
  items,
  active,
  navigationLabel,
  navigationAriaLabel,
  eyebrow,
  title,
  description,
  actions,
  className = "",
}: DomainShellProps) {
  return (
    <main className="app-shell">
      <PageWorkspace className={`domain-workspace ${className}`.trim()}>
        <DomainNavigation
          items={items}
          active={active}
          label={navigationLabel}
          ariaLabel={navigationAriaLabel}
        />
        <PageHeader eyebrow={eyebrow} title={title} description={description} actions={actions} />
        {children}
      </PageWorkspace>
    </main>
  );
}

export function Panel({ children, className = "" }: PageWorkspaceProps) {
  return <section className={`panel canonical-panel ${className}`.trim()}>{children}</section>;
}

export function FormSection({ title, description, children }: PageWorkspaceProps & { title: string; description?: string }) {
  return (
    <fieldset className="form-section">
      <legend>{title}</legend>
      {description ? <p className="muted">{description}</p> : null}
      {children}
    </fieldset>
  );
}

export function EmptyState({ title, description, actions }: { title: string; description: string; actions?: ReactNode }) {
  return <State kind="empty" title={title} description={description} actions={actions} />;
}

export function ErrorState({ title, description, actions }: { title: string; description: string; actions?: ReactNode }) {
  return <State kind="error" title={title} description={description} actions={actions} />;
}

export function PermissionState({ title, description, actions }: { title: string; description: string; actions?: ReactNode }) {
  return <State kind="blocked" title={title} description={description} actions={actions} />;
}

function State({ kind, title, description, actions }: { kind: string; title: string; description: string; actions?: ReactNode }) {
  return (
    <section className={`shell-state shell-state-${kind}`}>
      <h2>{title}</h2>
      <p className="muted">{description}</p>
      {actions ? <div className="shell-state-actions">{actions}</div> : null}
    </section>
  );
}
