# ------------------------------------------------------------------------------
# Warehouse Configuration
# ------------------------------------------------------------------------------

resource "snowflake_warehouse" "compute_wh" {
  name           = "COMPUTE_WH"
  warehouse_size = "X-SMALL"
  auto_suspend   = 60
  auto_resume    = true
  comment        = "Warehouse for ingestion and deployment tasks"
}