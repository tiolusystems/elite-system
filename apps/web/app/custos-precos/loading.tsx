import styles from "./pricing.module.css";

export default function CostPricingLoading() {
  return <main className={styles.workspace} aria-busy="true" aria-live="polite">
    <header className={styles.heading}><div><span className="eyebrow">Precificacao</span><h1>Formacao de custos e precos</h1><p>Carregando a memoria de custos e precos.</p></div><span className="status-chip">Carregando</span></header>
    <section className={`${styles.band} ${styles.loading}`}><div /><div /><div /></section>
  </main>;
}
