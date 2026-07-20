type DeveloperSignatureProps = {
  className?: string;
};

export function DeveloperSignature({ className }: DeveloperSignatureProps) {
  const classes = ["developer-signature", className].filter(Boolean).join(" ");

  return (
    <span className={classes} aria-label="by ☧ SYSTEMS">
      by <span aria-hidden="true">☧</span> SYSTEMS
    </span>
  );
}
