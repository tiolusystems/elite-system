import { createVehicleAction, setVehicleActiveStateAction } from "@/app/cadastros/actions";
import type { MasterDataVehicle } from "@/lib/master-data";
import { cadastroStatusLabel } from "@/lib/master-data-governance";

type VehiclesSectionProps = {
  busca: string;
  canCreate: boolean;
  canManageStatus: boolean;
  vehicles: MasterDataVehicle[];
};

export function VehiclesSection({
  busca,
  canCreate,
  canManageStatus,
  vehicles
}: VehiclesSectionProps) {
  const normalizedQuery = busca.trim().toLocaleLowerCase("pt-BR");
  const visibleVehicles = vehicles.filter((vehicle) =>
    !normalizedQuery ||
    `${vehicle.description} ${vehicle.plate ?? ""} ${vehicle.legacyCode ?? ""}`
      .toLocaleLowerCase("pt-BR")
      .includes(normalizedQuery)
  );

  return (
    <>
      <section className="panel cadastros-focused-panel" aria-labelledby="vehicle-list-title">
        <div className="panel-header">
          <div>
            <span className="eyebrow">Apoio a expedicao</span>
            <h2 id="vehicle-list-title">Veiculos cadastrados</h2>
          </div>
          <span className="pill">{visibleVehicles.length} registro(s)</span>
        </div>

        {visibleVehicles.length > 0 ? (
          <div className="catalog-linked-records">
            {visibleVehicles.map((vehicle) => (
              <article className="catalog-linked-row" key={vehicle.id}>
                <span>
                  <strong>{vehicle.description}</strong>
                  <small>{vehicle.plate ?? "Placa nao informada"}</small>
                </span>
                <span className={`status-chip status-${vehicle.status}`}>
                  {cadastroStatusLabel(vehicle.status)}
                </span>
                {canManageStatus && ["active", "inactive"].includes(vehicle.status) ? (
                  <form action={setVehicleActiveStateAction}>
                    <input type="hidden" name="veiculo_id" value={vehicle.id} />
                    <input type="hidden" name="active" value={vehicle.status === "inactive" ? "true" : "false"} />
                    <label>
                      <small>Justificativa</small>
                      <input name="motivo" minLength={10} placeholder="Justificativa obrigatoria" required />
                    </label>
                    <button className="secondary-button compact-button" type="submit">
                      {vehicle.status === "inactive" ? "Reativar" : "Inativar"}
                    </button>
                  </form>
                ) : (
                  <small>
                    {vehicle.status === "pending_review"
                      ? "Cadastro aguardando revisao."
                      : "Sem alcada para alterar a situacao."}
                  </small>
                )}
              </article>
            ))}
          </div>
        ) : (
          <div className="empty-state">
            <strong>Nenhum veiculo encontrado</strong>
            <span>Revise a busca ou cadastre o primeiro veiculo autorizado para entrega.</span>
          </div>
        )}
      </section>

      <section className="panel form-panel cadastros-focused-panel" id="novo-veiculo">
        <div className="panel-header">
          <div>
            <span className="eyebrow">Cadastro governado</span>
            <h2>Novo veiculo</h2>
          </div>
        </div>
        {canCreate ? (
          <form action={createVehicleAction}>
            <div className="form-grid">
              <label>
                Descricao
                <input name="descricao" placeholder="Ex.: Caminhao de entregas" required />
              </label>
              <label>
                Placa
                <input name="placa" autoCapitalize="characters" placeholder="ABC1D23" required />
              </label>
              <label className="form-grid-wide">
                Codigo legado
                <input name="codigo_legado" placeholder="Opcional" />
              </label>
            </div>
            <div className="form-footer">
              <span>A placa e normalizada para impedir cadastros duplicados.</span>
              <button className="primary-button" type="submit">Cadastrar veiculo</button>
            </div>
          </form>
        ) : (
          <div className="shell-state shell-state-blocked">
            <strong>Cadastro somente para usuarios autorizados</strong>
            <span>Voce pode consultar os veiculos, mas nao possui alcada individual para cadastrar.</span>
          </div>
        )}
      </section>
    </>
  );
}
