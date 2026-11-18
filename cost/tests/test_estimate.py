import json
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent))

import estimate as cost  # noqa: E402

PRICES = {
    "run_vcpu_second": 0.000024,
    "run_gib_second": 0.0000025,
    "run_million_requests": 0.4,
    "sql_micro_hour": 0.015,
    "sql_hdd_gb_month": 0.09,
    "secret_version_month": 0.06,
    "secret_10k_access": 0.03,
    "gcs_gb_month": 0.02,
    "gcs_10k_class_a": 0.05,
    "registry_gb_month": 0.1,
}
REGION = "us-central1"


def book():
    return cost.PriceBook({REGION: PRICES}, offline=True)


def usage(**overrides):
    base = json.loads((HERE.parent / "usage.json").read_text())
    base.update(overrides)
    return base


def app(cpu="1", memory="512Mi"):
    return {
        "address": "module.stack.module.app.google_cloud_run_v2_service.this",
        "mode": "managed",
        "type": "google_cloud_run_v2_service",
        "values": {
            "location": REGION,
            "template": [{"containers": [{"resources": [{"limits": {"cpu": cpu, "memory": memory}}]}]}],
        },
    }


def database():
    return {
        "address": "module.stack.module.database.google_sql_database_instance.this",
        "mode": "managed",
        "type": "google_sql_database_instance",
        "values": {"region": REGION, "settings": [{"tier": "db-f1-micro"}]},
    }


def plan(*resources):
    return {"planned_values": {"root_module": {"child_modules": [{"resources": list(resources)}]}}}


def registry():
    return {
        "address": "google_artifact_registry_repository.ledger",
        "mode": "managed",
        "type": "google_artifact_registry_repository",
        "values": {"location": REGION},
    }


def total(lines):
    return sum(line.monthly_usd for line in lines)


def test_free_grant_covers_light_usage():
    lines, unknown = cost.estimate({"dev": plan(app())}, usage(), book())
    assert total(lines) == 0
    assert unknown == []


def test_usage_over_grant_is_billed():
    hours = {"dev": 1000}
    lines, _ = cost.estimate(
        {"dev": plan(app())}, usage(app_active_hours_per_month=hours), book()
    )
    # 3.6M segundos x 1 vCPU - 180k gratis; x 0.5 GiB - 360k gratis.
    assert total(lines) == pytest.approx(3_420_000 * 0.000024 + 1_440_000 * 0.0000025)


def test_grant_is_shared_between_environments():
    hours = {"dev": 40, "prod": 40}
    alone, _ = cost.estimate(
        {"dev": plan(app())}, usage(app_active_hours_per_month=hours), book()
    )
    both, _ = cost.estimate(
        {"dev": plan(app()), "prod": plan(app())},
        usage(app_active_hours_per_month=hours), book(),
    )
    assert total(alone) == 0
    assert total(both) > 0


def test_cloud_sql_always_bills_because_it_has_no_free_tier():
    lines, _ = cost.estimate({"dev": plan(database())}, usage(), book())
    assert total(lines) == pytest.approx(730 * 0.015 + 10 * 0.09)


def test_unknown_resource_is_reported():
    vm = {"address": "google_compute_instance.x", "mode": "managed",
          "type": "google_compute_instance", "values": {}}
    _, unknown = cost.estimate({"dev": plan(vm)}, usage(), book())
    assert unknown == ["dev: google_compute_instance.x"]


def test_data_sources_and_helpers_are_ignored():
    data = {"address": "data.x", "mode": "data", "type": "google_project", "values": {}}
    helper = {"address": "random_string.s", "mode": "managed", "type": "random_string", "values": {}}
    lines, unknown = cost.estimate({"dev": plan(data, helper)}, usage(), book())
    assert lines == [] and unknown == []


def test_network_failure_falls_back_to_snapshot():
    def broken(_key, _region):
        raise OSError("sin red")

    prices = cost.PriceBook({REGION: PRICES}, fetcher=broken)
    assert prices.price("secret_10k_access", REGION) == 0.03
    assert prices.used_snapshot


def test_missing_price_is_an_error_not_zero():
    with pytest.raises(cost.PriceNotFound):
        cost.PriceBook({}, offline=True).price("secret_10k_access", REGION)


def run_cli(tmp_path, resources, *extra):
    path = tmp_path / "plan.json"
    path.write_text(json.dumps(plan(*resources)))
    snapshot = tmp_path / "prices.json"
    snapshot.write_text(json.dumps({REGION: PRICES}))
    return cost.main([
        "--plan", f"dev={path}", "--snapshot", str(snapshot), "--offline", *extra,
    ])


def test_budget_gate_fails_when_exceeded(tmp_path):
    assert run_cli(tmp_path, [database()], "--budget", "1") == 1


def test_budget_gate_passes_within_limit(tmp_path):
    assert run_cli(tmp_path, [database()], "--budget", "20") == 0


def test_unknown_resource_fails_the_gate(tmp_path):
    vm = {"address": "google_compute_instance.x", "mode": "managed",
          "type": "google_compute_instance", "values": {}}
    assert run_cli(tmp_path, [vm]) == 1


def test_registry_within_free_gb_costs_zero():
    lines, unknown = cost.estimate({"dev": plan(registry())}, usage(registry_storage_gb=0.5), book())
    assert total(lines) == 0 and unknown == []


def test_registry_storage_over_free_gb_is_billed():
    lines, _ = cost.estimate({"dev": plan(registry())}, usage(registry_storage_gb=2.5), book())
    # 2,5 GB - 0,5 GB gratis = 2 GB x 0,10 USD
    assert total(lines) == pytest.approx(0.2)
    assert "2.5 GB" in lines[0].detail


def test_registry_without_price_fails_instead_of_costing_zero():
    prices = {k: v for k, v in PRICES.items() if k != "registry_gb_month"}
    with pytest.raises(cost.PriceNotFound):
        cost.estimate({"dev": plan(registry())}, usage(),
                      cost.PriceBook({REGION: prices}, offline=True))
