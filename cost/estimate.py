#!/usr/bin/env python3
"""Estima el costo mensual desde `terraform show -json`.

Los precios salen de una copia local (prices-snapshot.json) de las tarifas publicas de GCP. Si
defines GCP_BILLING_API_KEY, se consulta ademas la Cloud Billing Catalog API para refrescarlos.
Solo depende de la biblioteca estandar. El consumo no aparece en un plan, por eso se declara en
usage.json.
"""

import argparse
import json
import os
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

CATALOG_URL = "https://cloudbilling.googleapis.com/v1/services"
HERE = Path(__file__).parent

# clave: (ID del servicio en el catalogo, texto que debe contener la descripcion del SKU)
METERS = {
    "run_vcpu_second": ("152E-C115-5142", "CPU Allocation Time"),
    "run_gib_second": ("152E-C115-5142", "Memory Allocation Time"),
    "run_million_requests": ("152E-C115-5142", "Requests"),
    "sql_micro_hour": ("9662-B51E-5089", "Micro instance"),
    "sql_hdd_gb_month": ("9662-B51E-5089", "HDD storage"),
    "secret_version_month": ("EE2C-7FAC-5E08", "Secret version replica storage"),
    "secret_10k_access": ("EE2C-7FAC-5E08", "Secret access operations"),
    "gcs_gb_month": ("95FF-2EF5-5EA1", "Standard Storage"),
    "gcs_10k_class_a": ("95FF-2EF5-5EA1", "Class A Operations"),
}

# Recursos sin cargo propio: su costo aparece, si lo hay, en los recursos que los usan.
FREE_RESOURCES = {
    "google_project_iam_member",
    "google_service_account",
    "google_service_account_iam_member",
    "google_secret_manager_secret_iam_member",
    "google_cloud_run_v2_service_iam_member",
    "google_sql_database",
    "google_sql_user",
    "google_logging_metric",  # Las metricas basadas en logs no tienen cargo.
    "google_iam_workload_identity_pool",
    "google_iam_workload_identity_pool_provider",
    "google_storage_bucket_iam_member",
    "google_artifact_registry_repository_iam_member",
}


class PriceNotFound(Exception):
    pass


def fetch_live_price(key: str, region: str) -> float:
    api_key = os.environ.get("GCP_BILLING_API_KEY")
    if not api_key:
        raise OSError("falta GCP_BILLING_API_KEY")
    service, text = METERS[key]
    url = f"{CATALOG_URL}/{service}/skus?{urllib.parse.urlencode({'key': api_key})}"
    prices = []
    while url:
        with urllib.request.urlopen(url, timeout=30) as response:
            page = json.load(response)
        for sku in page.get("skus", []):
            if text.lower() in sku["description"].lower() and region in sku.get("serviceRegions", []):
                rate = sku["pricingInfo"][0]["pricingExpression"]["tieredRates"][-1]["unitPrice"]
                prices.append(int(rate.get("units", 0)) + rate.get("nanos", 0) / 1e9)
        token = page.get("nextPageToken")
        url = f"{CATALOG_URL}/{service}/skus?{urllib.parse.urlencode({'key': api_key, 'pageToken': token})}" if token else None
    if not prices:
        raise PriceNotFound(f"Sin precio para {key} en {region}")
    return max(prices)


class PriceBook:
    """Precios en vivo con respaldo a una copia local, para no bloquearse sin red."""

    def __init__(self, snapshot: dict, offline: bool = False, fetcher=fetch_live_price):
        self.snapshot = snapshot
        self.offline = offline
        self.fetcher = fetcher
        self.cache: dict[tuple[str, str], float] = {}
        self.used_snapshot = False

    def price(self, key: str, region: str) -> float:
        if (key, region) in self.cache:
            return self.cache[(key, region)]
        value = None
        if not self.offline:
            try:
                value = self.fetcher(key, region)
            except OSError as error:
                print(f"Aviso: sin acceso a la API de precios ({error})", file=sys.stderr)
        if value is None:
            try:
                value = self.snapshot[region][key]
            except KeyError as error:
                raise PriceNotFound(f"Sin copia local de {key} en {region}") from error
            self.used_snapshot = True
        self.cache[(key, region)] = value
        return value


@dataclass
class Line:
    environment: str
    address: str
    monthly_usd: float
    detail: str


def walk_resources(module: dict):
    yield from module.get("resources", [])
    for child in module.get("child_modules", []):
        yield from walk_resources(child)


def plan_resources(plan: dict) -> list[dict]:
    root = plan.get("planned_values", {}).get("root_module", {})
    return [r for r in walk_resources(root) if r.get("mode") == "managed"]


def plan_region(resources: list[dict], fallback: str) -> str:
    for resource in resources:
        values = resource.get("values", {})
        location = values.get("location") or values.get("region")
        if location:
            return location.replace(" ", "").lower()
    return fallback


def parse_gib(memory: str) -> float:
    memory = memory.strip()
    if memory.endswith("Mi"):
        return float(memory.removesuffix("Mi")) / 1024
    return float(memory.removesuffix("Gi"))


def estimate_plan(name: str, plan: dict, usage: dict, book: PriceBook, grant: dict) -> tuple:
    """Devuelve las lineas de costo y los recursos sin regla de precio."""
    resources = plan_resources(plan)
    region = plan_region(resources, usage.get("default_region", "us-central1"))
    lines, unknown = [], []

    for resource in resources:
        kind, values, address = resource["type"], resource.get("values", {}), resource["address"]
        if kind in FREE_RESOURCES or kind.startswith(("random_", "time_")):
            continue
        if kind == "google_cloud_run_v2_service":
            lines.append(_cloud_run(name, address, values, usage, region, book, grant))
        elif kind == "google_sql_database_instance":
            lines.append(_database(name, address, values, usage, region, book))
        elif kind == "google_secret_manager_secret":
            operations = usage["secret_accesses_per_month"]
            cost = (
                usage["secret_versions"] * book.price("secret_version_month", region)
                + operations / 10_000 * book.price("secret_10k_access", region)
            )
            lines.append(Line(name, address, cost, f"{operations:,} accesos"))
        elif kind == "google_storage_bucket":
            storage = usage["state_storage_gb"] * book.price("gcs_gb_month", region)
            writes = usage["state_writes_per_month"] / 10_000 * book.price("gcs_10k_class_a", region)
            lines.append(Line(name, address, storage + writes, f"{usage['state_storage_gb']} GB"))
        elif kind in ("google_secret_manager_secret_version", "google_artifact_registry_repository"):
            lines.append(Line(name, address, 0.0, "dentro de la capa gratuita"))
        else:
            unknown.append(address)
    return lines, unknown


def _cloud_run(env, address, values, usage, region, book, grant) -> Line:
    limits = values["template"][0]["containers"][0]["resources"][0]["limits"]
    seconds = usage["app_active_hours_per_month"][env] * 3600
    vcpu_seconds = seconds * float(limits["cpu"])
    gib_seconds = seconds * parse_gib(limits["memory"])
    requests = usage["requests_per_month"][env]

    # La capa gratuita es por cuenta de facturacion: dev y prod consumen de la misma bolsa.
    def consume(name: str, amount: float) -> float:
        covered = min(grant[name], amount)
        grant[name] -= covered
        return amount - covered

    cost = (
        consume("vcpu_seconds", vcpu_seconds) * book.price("run_vcpu_second", region)
        + consume("gib_seconds", gib_seconds) * book.price("run_gib_second", region)
        + consume("requests", requests) / 1e6 * book.price("run_million_requests", region)
    )
    return Line(env, address, cost, f"{seconds / 3600:.0f} h activas, {requests:,} solicitudes")


def _database(env, address, values, usage, region, book) -> Line:
    # Cloud SQL no se pausa ni tiene oferta gratuita: la instancia cobra todas las horas encendida.
    hours = usage["database_hours_per_month"][env]
    compute = hours * book.price("sql_micro_hour", region)
    storage = usage["database_storage_gb"] * book.price("sql_hdd_gb_month", region)
    return Line(env, address, compute + storage, f"{hours} h de instancia, {usage['database_storage_gb']} GB HDD")


def estimate(plans: dict[str, dict], usage: dict, book: PriceBook) -> tuple:
    grant = dict(usage["cloud_run_free_grant"])
    lines, unknown = [], []
    for name, plan in plans.items():
        plan_lines, plan_unknown = estimate_plan(name, plan, usage, book, grant)
        lines += plan_lines
        unknown += [f"{name}: {address}" for address in plan_unknown]
    return lines, unknown


def render(lines: list[Line], unknown: list[str], budget: float | None) -> str:
    width = max([len(line.address) for line in lines] + [7])
    rows = [f"{'Ambiente':<9} {'Recurso':<{width}} {'USD/mes':>9}  Supuesto"]
    rows += [
        f"{line.environment:<9} {line.address:<{width}} {line.monthly_usd:>9.2f}  {line.detail}"
        for line in lines
    ]
    total = sum(line.monthly_usd for line in lines)
    rows.append(f"{'TOTAL':<9} {'':<{width}} {total:>9.2f}")
    if budget is not None:
        rows.append(f"Presupuesto: {budget:.2f} USD/mes")
    rows += [f"SIN PRECIO: {address}" for address in unknown]
    return "\n".join(rows)


def refresh_snapshot(path: Path, region: str) -> None:
    snapshot = json.loads(path.read_text()) if path.exists() else {}
    snapshot[region] = {key: fetch_live_price(key, region) for key in METERS}
    path.write_text(json.dumps(snapshot, indent=2, sort_keys=True) + "\n")


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--plan", action="append", default=[], metavar="AMBIENTE=ARCHIVO",
        help="Plan JSON de terraform; se puede repetir, p. ej. --plan dev=dev.json",
    )
    parser.add_argument("--usage", type=Path, default=HERE / "usage.json")
    parser.add_argument("--snapshot", type=Path, default=HERE / "prices-snapshot.json")
    parser.add_argument("--offline", action="store_true", help="Usa solo la copia local de precios")
    parser.add_argument("--budget", type=float, help="Falla si el total mensual lo supera")
    parser.add_argument("--refresh-snapshot", metavar="REGION", help="Actualiza la copia local")
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    if args.refresh_snapshot:
        refresh_snapshot(args.snapshot, args.refresh_snapshot)
        print(f"Copia de precios actualizada para {args.refresh_snapshot}")
        return 0
    if not args.plan:
        print("Indica al menos un --plan AMBIENTE=ARCHIVO", file=sys.stderr)
        return 2

    plans = {}
    for item in args.plan:
        name, _, filename = item.partition("=")
        plans[name] = json.loads(Path(filename).read_text())
    snapshot = json.loads(args.snapshot.read_text()) if args.snapshot.exists() else {}
    book = PriceBook(snapshot, offline=args.offline)
    usage = json.loads(args.usage.read_text())

    try:
        lines, unknown = estimate(plans, usage, book)
    except PriceNotFound as error:
        print(f"Error: {error}", file=sys.stderr)
        return 2

    print(render(lines, unknown, args.budget))
    if book.used_snapshot:
        print("Aviso: se usaron precios de la copia local; pueden estar desactualizados.")
    # Un recurso sin regla volveria engañoso el total, asi que tambien detiene el despliegue.
    if unknown:
        print("Error: agrega una regla de precio para los recursos listados.", file=sys.stderr)
        return 1
    total = sum(line.monthly_usd for line in lines)
    if args.budget is not None and total > args.budget:
        print(f"Error: {total:.2f} USD supera el presupuesto.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
