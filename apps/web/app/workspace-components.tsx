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

export type WorkspaceFact = {
  readonly id: string;
  readonly label: string;
  readonly value: ReactNode;
};

export type GovernedWorkflowState =
  | "complete"
  | "available"
  | "waiting"
  | "blocked"
  | "neutral";

export type GovernedWorkflowStep<TId extends string> = {
  readonly id: TId;
  readonly href: string;
  readonly title: string;
  readonly label: string;
  readonly state: GovernedWorkflowState;
};

type GovernedWorkflowStepperProps<TId extends string> = {
  readonly steps: readonly GovernedWorkflowStep<TId>[];
  readonly selectedId: NoInfer<TId>;
  readonly currentId: NoInfer<TId>;
  readonly ariaLabel: string;
};

type OperationalWorkspaceProps = PageWorkspaceProps & {
  as?: "main" | "div";
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

export type ExportMenuItem = {
  label: string;
  href: string;
  description?: string;
  primary?: boolean;
};

type ExportMenuProps = {
  items: ExportMenuItem[];
  label?: string;
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

export function OperationalWorkspace({
  children,
  className = "",
  as = "main",
}: OperationalWorkspaceProps) {
  const classNames = `operational-workspace ${className}`.trim();

  if (as === "div") {
    return <div className={classNames}>{children}</div>;
  }

  return <main className={classNames}>{children}</main>;
}

export function OperationalPageHeader({
  eyebrow,
  title,
  description,
  facts = [],
  actions,
}: PageHeaderProps & { facts?: readonly WorkspaceFact[] }) {
  return (
    <header className="operational-page-header">
      <div className="operational-page-header-copy">
        {eyebrow ? <span className="eyebrow">{eyebrow}</span> : null}
        <h1>{title}</h1>
        <p>{description}</p>
      </div>
      {facts.length ? (
        <dl className="operational-page-facts">
          {facts.map((fact) => (
            <div key={fact.id}>
              <dt>{fact.label}</dt>
              <dd>{fact.value}</dd>
            </div>
          ))}
        </dl>
      ) : null}
      {actions ? <div className="operational-page-actions">{actions}</div> : null}
    </header>
  );
}

export function GovernedWorkflowStepper<const TId extends string>({
  steps,
  selectedId,
  currentId,
  ariaLabel,
}: GovernedWorkflowStepperProps<TId>) {
  return (
    <nav className="governed-workflow-stepper" aria-label={ariaLabel}>
      <ol>
        {steps.map((step, index) => {
          const isSelected = step.id === selectedId;
          const isCurrent = step.id === currentId;

          return (
            <li key={step.id} data-state={step.state} data-current={isCurrent || undefined}>
              <Link href={step.href} aria-current={isSelected ? "page" : undefined}>
                <span className="governed-workflow-stepper-number">{index + 1}</span>
                <span>
                  <strong>{step.title}</strong>
                  <small>{step.label}</small>
                  {isCurrent ? (
                    <span className={isSelected ? "governed-workflow-stepper-current-sr" : "governed-workflow-stepper-current"}>
                      Etapa atual do processo
                    </span>
                  ) : null}
                </span>
              </Link>
            </li>
          );
        })}
      </ol>
    </nav>
  );
}

export function OperationalWorkspaceLayout({ children }: { children: ReactNode }) {
  return (
    <div className="operational-workspace-layout">
      {children}
    </div>
  );
}

export function OperationalWorkspaceSurface({ children, labelledBy }: { children: ReactNode; labelledBy: string }) {
  return (
    <section className="operational-workspace-surface" aria-labelledby={labelledBy}>
      {children}
    </section>
  );
}

export function OperationalWorkspaceBody({ children }: { children: ReactNode }) {
  return <div className="operational-workspace-body">{children}</div>;
}

export function OperationalContextPanel({
  rows,
  note,
  ariaLabel,
}: {
  rows: readonly WorkspaceFact[];
  note?: ReactNode;
  ariaLabel: string;
}) {
  return (
    <aside className="operational-context-panel" aria-label={ariaLabel}>
      <dl>
        {rows.map((row) => (
          <div key={row.id}>
            <dt>{row.label}</dt>
            <dd>{row.value}</dd>
          </div>
        ))}
      </dl>
      {note != null ? <small>{note}</small> : null}
    </aside>
  );
}

export function OperationalStageHeader({
  id,
  number,
  eyebrow,
  title,
  description,
  status,
  state,
}: {
  id: string;
  number: string;
  eyebrow: string;
  title: string;
  description: string;
  status: string;
  state: GovernedWorkflowState;
}) {
  return (
    <header className="operational-stage-header" data-state={state}>
      <div className="operational-stage-title">
        <span>{number}</span>
        <div>
          <p className="eyebrow">{eyebrow}</p>
          <h2 id={id}>{title}</h2>
          <p className="operational-stage-description">{description}</p>
        </div>
      </div>
      <span className="status-chip">{status}</span>
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

export function ExportMenu({ items, label = "Exportar" }: ExportMenuProps) {
  return (
    <details className="export-menu">
      <summary className="secondary-button export-menu-trigger">
        <span>{label}</span>
        <span aria-hidden="true">▾</span>
      </summary>
      <div className="export-menu-options">
        {items.map((item) => (
          <a
            className={`export-menu-option ${item.primary ? "export-menu-option-primary" : ""}`.trim()}
            href={item.href}
            key={`${item.label}-${item.href}`}
          >
            <span className="export-menu-option-copy">
              <strong>{item.label}</strong>
              {item.description ? <small>{item.description}</small> : null}
            </span>
            {item.primary ? <span className="export-menu-badge">Principal</span> : null}
          </a>
        ))}
      </div>
    </details>
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
