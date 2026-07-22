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
