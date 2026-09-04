import { Button, InlineNotification, SkeletonPlaceholder, SkeletonText } from "@carbon/react";
import { ArrowRight } from "@carbon/icons-react";

export function SectionLabel({ index, children, inverse = false }) {
  return (
    <p className={`section-label${inverse ? " section-label--inverse" : ""}`}>
      <span aria-hidden="true">{index}</span>
      {children}
    </p>
  );
}

export function SignalHero({
  index,
  eyebrow,
  title,
  accent,
  description,
  action,
  metrics = [],
  tone = "blue",
  visualLabel = "Live system view",
}) {
  return (
    <header className={`signal-hero signal-hero--${tone}`}>
      <div className="signal-hero__copy">
        <SectionLabel index={index}>{eyebrow}</SectionLabel>
        <h1>
          {title}
          {accent && <span>{accent}</span>}
        </h1>
        {description && <p className="signal-hero__description">{description}</p>}
        {action && <div className="signal-hero__action">{action}</div>}
      </div>
      <div className="signal-hero__visual">
        <span
          className="signal-hero__coordinate signal-hero__coordinate--top"
          aria-hidden="true"
        >
          x.16 / y.08
        </span>
        <span
          className="signal-hero__coordinate signal-hero__coordinate--bottom"
          aria-hidden="true"
        >
          08 PX MINI UNIT
        </span>
        <div className="signal-hero__axis signal-hero__axis--x" aria-hidden="true" />
        <div className="signal-hero__axis signal-hero__axis--y" aria-hidden="true" />
        <div className="signal-hero__signal" aria-hidden="true">
          <span />
          <span />
          <span />
        </div>
        <p>{visualLabel}</p>
        {metrics.length > 0 && (
          <dl className="signal-hero__metrics" aria-label={`${eyebrow} summary`}>
            {metrics.map(({ label, value }) => (
              <div key={label}>
                <dt>{label}</dt>
                <dd>{value}</dd>
              </div>
            ))}
          </dl>
        )}
      </div>
    </header>
  );
}

export function SectionHeading({ index, eyebrow, title, description, action }) {
  return (
    <div className="signal-section-heading">
      <div>
        <SectionLabel index={index}>{eyebrow}</SectionLabel>
        <h2>{title}</h2>
        {description && <p>{description}</p>}
      </div>
      {action && <div className="signal-section-heading__action">{action}</div>}
    </div>
  );
}

export function AuthFrame({ index, eyebrow, title, accent, description, children, footer }) {
  return (
    <div className="auth-frame">
      <section className="auth-frame__visual" aria-label="bacon-net player network">
        <div className="auth-frame__diagram">
          <span
            className="auth-frame__coordinate auth-frame__coordinate--top"
            aria-hidden="true"
          >
            X.00 / Y.00
          </span>
          <div className="auth-frame__node auth-frame__node--account" aria-hidden="true">
            ACCOUNT
          </div>
          <div className="auth-frame__node auth-frame__node--card" aria-hidden="true">
            CARD
          </div>
          <div className="auth-frame__node auth-frame__node--play" aria-hidden="true">
            PLAY
          </div>
          <svg
            viewBox="0 0 640 480"
            preserveAspectRatio="none"
            focusable="false"
            aria-hidden="true"
          >
            <path d="M96 112H272V240H432V352H560" />
            <circle cx="272" cy="240" r="5" />
            <circle cx="432" cy="352" r="5" />
          </svg>
          <p>
            ONE IDENTITY
            <br />
            EVERY CABINET
          </p>
          <span
            className="auth-frame__coordinate auth-frame__coordinate--bottom"
            aria-hidden="true"
          >
            08 PX / SYSTEM GRID
          </span>
        </div>
      </section>
      <section className="auth-frame__form">
        <div className="auth-frame__form-inner">
          <SectionLabel index={index}>{eyebrow}</SectionLabel>
          <h1>
            {title}
            {accent && <span>{accent}</span>}
          </h1>
          <p className="auth-frame__intro">{description}</p>
          <div className="auth-frame__fields">{children}</div>
          {footer && <p className="auth-frame__footer">{footer}</p>}
        </div>
      </section>
    </div>
  );
}

export function PageState({ kind = "loading", title, description, onRetry }) {
  if (kind === "loading") {
    return (
      <div className="signal-page signal-state" aria-busy="true" aria-label={title}>
        <div className="signal-state__copy">
          <SectionLabel index="00">Loading</SectionLabel>
          <h1 className="sr-only">{title}</h1>
          <SkeletonText heading width="55%" />
          <SkeletonText width="75%" paragraph lineCount={2} />
        </div>
        <SkeletonPlaceholder className="signal-state__plane" />
      </div>
    );
  }

  return (
    <div className="signal-page signal-state">
      <div className="signal-state__copy">
        <SectionLabel index="!!">{kind === "error" ? "System notice" : "Ready state"}</SectionLabel>
        <h1>{title}</h1>
        {description && <p>{description}</p>}
        {onRetry && (
          <Button onClick={onRetry} renderIcon={ArrowRight}>
            Try again
          </Button>
        )}
      </div>
      <InlineNotification
        kind={kind === "error" ? "error" : "info"}
        title={title}
        subtitle={description}
        hideCloseButton
        lowContrast
      />
    </div>
  );
}
